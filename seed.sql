-- DEMO DATA ONLY. Not verified menu or prices. Replace via the admin dashboard.
insert into categories(name,sort) values ('South Indian',1),('North Indian',2),('Chinese',3),('Pizza & Pasta',4),('Burgers',5),('Rice & Biryani',6),('Beverages',7),('Desserts',8) on conflict do nothing;
insert into products(category_id,name,description,price_inr,prep_minutes,is_demo)
select c.id,v.n,v.d,v.p,v.t,true from (values
('South Indian','Masala Dosa','Crisp rice crepe with spiced potato filling.',99,15),
('South Indian','Idli Sambar','Steamed rice cakes with sambar.',69,10),
('South Indian','Vada Sambar','Lentil fritters in sambar.',79,10),
('South Indian','Onion Uttapam','Rice pancake with onion.',109,15),
('North Indian','Paneer Butter Masala','Paneer in creamy tomato gravy.',189,20),
('Chinese','Veg Fried Rice','Wok-tossed rice with vegetables.',129,15),
('Chinese','Hakka Noodles','Stir-fried noodles.',129,15),
('Pizza & Pasta','Margherita Pizza','Tomato and mozzarella.',179,20),
('Burgers','Veg Burger','Veg patty with salad.',89,12),
('Beverages','Cold Coffee','Chilled and creamy.',99,5)
) as v(cat,n,d,p,t) join categories c on c.name = v.cat;
insert into delivery_zones(name,fee_inr,min_order_inr) values ('Demo zone: Medical Chauraha',30,149);
insert into tables(label,seats) select 'T'||g, 4 from generate_series(1,6) g;
