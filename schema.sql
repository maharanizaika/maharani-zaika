-- Maharani Zaika: core schema + RLS. Run in Supabase SQL Editor.
create extension if not exists pgcrypto;

create type app_role as enum ('customer','staff','admin');
create type order_status as enum ('placed','accepted','preparing','ready','out_for_delivery','delivered','cancelled');
create type order_type as enum ('delivery','takeaway','dine_in');
create type pay_status as enum ('pending','paid','failed','refunded');

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text, phone text,
  role app_role not null default 'customer',
  created_at timestamptz not null default now()
);
create or replace function is_role(r app_role[]) returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from profiles where id = auth.uid() and role = any(r)) $$;

create table categories (id serial primary key, name text unique not null, sort int default 0, active boolean default true);
create table products (
  id uuid primary key default gen_random_uuid(),
  category_id int references categories,
  name text not null, description text, image_url text,
  price_inr int not null check (price_inr >= 0),
  is_veg boolean not null default true,
  available boolean not null default true,
  prep_minutes int default 15, allergens text,
  is_demo boolean not null default false,
  created_at timestamptz default now()
);
create index on products(category_id);
create table product_options (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references products on delete cascade,
  label text not null, extra_price_inr int not null default 0 check (extra_price_inr >= 0)
);
create table tables (id serial primary key, label text unique not null, seats int not null check (seats > 0),
  qr_token text unique not null default encode(gen_random_bytes(16),'hex'), active boolean default true);
create table coupons (code text primary key, percent_off int check (percent_off between 1 and 100),
  max_off_inr int, min_order_inr int default 0, valid_until timestamptz, active boolean default true);
create table delivery_zones (id serial primary key, name text not null, fee_inr int not null default 0,
  min_order_inr int not null default 0, active boolean default true);
create table addresses (id uuid primary key default gen_random_uuid(), user_id uuid references profiles on delete cascade,
  line text not null, landmark text, pincode text);
create table restaurant_settings (key text primary key, value jsonb not null);

create table orders (
  id uuid primary key default gen_random_uuid(),
  order_no text unique not null default 'MZ'||lpad((floor(random()*1000000))::int::text,6,'0'),
  user_id uuid references profiles,
  type order_type not null, status order_status not null default 'placed',
  table_id int references tables,
  customer_name text not null, phone text not null, address text, notes text,
  subtotal_inr int not null, discount_inr int not null default 0, tax_inr int not null,
  delivery_fee_inr int not null default 0, total_inr int not null,
  coupon_code text, created_at timestamptz default now(), updated_at timestamptz default now()
);
create index on orders(user_id); create index on orders(status, created_at desc);
create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders on delete cascade,
  product_id uuid references products, name text not null,
  unit_price_inr int not null, qty int not null check (qty between 1 and 20)
);
create table payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders on delete cascade,
  method text not null, status pay_status not null default 'pending',
  provider_ref text, created_at timestamptz default now()
);
create table reservations (
  id uuid primary key default gen_random_uuid(), user_id uuid references profiles,
  table_id int references tables, slot timestamptz not null, guests int not null check (guests > 0),
  name text not null, phone text not null, notes text,
  status text not null default 'requested' check (status in ('requested','confirmed','cancel_requested','cancelled')),
  created_at timestamptz default now()
);
-- Server-side double-booking guard
create unique index no_double_booking on reservations(table_id, slot) where status in ('requested','confirmed');
create table reviews (id uuid primary key default gen_random_uuid(), user_id uuid references profiles,
  order_id uuid references orders, rating int check (rating between 1 and 5), body text, approved boolean default false);
create table notifications (id uuid primary key default gen_random_uuid(), user_id uuid references profiles,
  title text, body text, read boolean default false, created_at timestamptz default now());
create table audit_logs (id bigserial primary key, actor uuid, action text, detail jsonb, created_at timestamptz default now());

-- Place order: prices are read from the DB, never from the browser.
create or replace function place_order(p_type order_type, p_name text, p_phone text, p_address text,
  p_notes text, p_table_token text, p_coupon text, p_items jsonb)
returns orders language plpgsql security definer set search_path = public as $$
declare sub int := 0; disc int := 0; tax int; fee int := 0; r record; it jsonb; o orders; tid int; c coupons;
begin
  if jsonb_array_length(p_items) = 0 then raise exception 'Cart is empty'; end if;
  if p_type = 'dine_in' then
    select id into tid from tables where qr_token = p_table_token and active;
    if tid is null then raise exception 'Invalid table'; end if;
  end if;
  for it in select * from jsonb_array_elements(p_items) loop
    select * into r from products where id = (it->>'id')::uuid and available;
    if not found then raise exception 'Item unavailable'; end if;
    sub := sub + r.price_inr * least(greatest((it->>'qty')::int,1),20);
  end loop;
  if p_coupon is not null then
    select * into c from coupons where code = upper(p_coupon) and active and (valid_until is null or valid_until > now()) and sub >= min_order_inr;
    if found then disc := least(sub * c.percent_off / 100, coalesce(c.max_off_inr, sub)); end if;
  end if;
  tax := round((sub - disc) * 0.05);
  if p_type = 'delivery' then select coalesce(min(fee_inr),0) into fee from delivery_zones where active; end if;
  insert into orders(user_id,type,table_id,customer_name,phone,address,notes,subtotal_inr,discount_inr,tax_inr,delivery_fee_inr,total_inr,coupon_code)
  values (auth.uid(),p_type,tid,p_name,p_phone,p_address,p_notes,sub,disc,tax,fee,sub-disc+tax+fee,upper(p_coupon)) returning * into o;
  for it in select * from jsonb_array_elements(p_items) loop
    select * into r from products where id = (it->>'id')::uuid;
    insert into order_items(order_id,product_id,name,unit_price_inr,qty)
    values (o.id,r.id,r.name,r.price_inr,least(greatest((it->>'qty')::int,1),20));
  end loop;
  insert into payments(order_id,method) values (o.id,'cod');
  return o;
end $$;
grant execute on function place_order to anon, authenticated;

-- RLS
alter table profiles enable row level security; alter table categories enable row level security;
alter table products enable row level security; alter table product_options enable row level security;
alter table tables enable row level security; alter table coupons enable row level security;
alter table delivery_zones enable row level security; alter table addresses enable row level security;
alter table restaurant_settings enable row level security; alter table orders enable row level security;
alter table order_items enable row level security; alter table payments enable row level security;
alter table reservations enable row level security; alter table reviews enable row level security;
alter table notifications enable row level security; alter table audit_logs enable row level security;

create policy "public read menu" on categories for select using (active);
create policy "public read products" on products for select using (true);
create policy "public read options" on product_options for select using (true);
create policy "public read zones" on delivery_zones for select using (active);
create policy "public read settings" on restaurant_settings for select using (true);
create policy "admin manage menu" on products for all using (is_role('{admin}')) with check (is_role('{admin}'));
create policy "admin manage cats" on categories for all using (is_role('{admin}')) with check (is_role('{admin}'));
create policy "admin manage options" on product_options for all using (is_role('{admin}')) with check (is_role('{admin}'));
create policy "admin manage zones" on delivery_zones for all using (is_role('{admin}')) with check (is_role('{admin}'));
create policy "admin manage settings" on restaurant_settings for all using (is_role('{admin}')) with check (is_role('{admin}'));
create policy "admin manage coupons" on coupons for all using (is_role('{admin}')) with check (is_role('{admin}'));
create policy "admin manage tables" on tables for all using (is_role('{admin}')) with check (is_role('{admin}'));
create policy "own profile" on profiles for select using (id = auth.uid() or is_role('{admin}'));
create policy "update own profile" on profiles for update using (id = auth.uid()) with check (id = auth.uid() and role = (select role from profiles where id = auth.uid()));
create policy "own addresses" on addresses for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own orders" on orders for select using (user_id = auth.uid() or is_role('{staff,admin}'));
create policy "staff update orders" on orders for update using (is_role('{staff,admin}'));
create policy "own order items" on order_items for select using (exists (select 1 from orders o where o.id = order_id and (o.user_id = auth.uid() or is_role('{staff,admin}'))));
create policy "payments view" on payments for select using (exists (select 1 from orders o where o.id = order_id and o.user_id = auth.uid()) or is_role('{admin}'));
create policy "own reservations" on reservations for select using (user_id = auth.uid() or is_role('{staff,admin}'));
create policy "make reservation" on reservations for insert with check (user_id = auth.uid() or user_id is null);
create policy "manage reservations" on reservations for update using (is_role('{staff,admin}'));
create policy "own notifications" on notifications for select using (user_id = auth.uid());
create policy "admin audit" on audit_logs for select using (is_role('{admin}'));
-- Payments are written only by place_order and the server webhook (service role bypasses RLS).
-- Guest tracking by order_no should go through a small Edge Function, not an open select.

create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
begin insert into profiles(id, full_name) values (new.id, new.raw_user_meta_data->>'full_name'); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();
