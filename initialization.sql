# INSERT INTO routes(color, grade_v, date_set) values ('blue', 5, '2020-

-- insert into gyms(gym_name, address, city, state, country, zip) values ("Central Rock Gym - North Station", "99 Beverly Street", "Boston", "MA", "USA", "02114");
-- insert into gyms(gym_name, address, city, state, country, zip) values ("Central Rock Gym - Watertown", "74 Acton St", "Watertown", "MA", "USA", "02472");
-- insert into gyms(gym_name, address, city, state, country, zip) values ("Central Rock Gym - Stoneham", "10 Adam Rd", "Stoneham", "MA", "USA", "02180");
-- 
-- insert into routes(gym_id, order_left, route_name, color, grade_v, date_set) values (1, 1, "test_route_1", "blue", 5, "2020-01-01");
-- 
-- show index from routes;
-- 
-- alter table `routes` add unique (`gym_id`, `color`, `grade_v`, `date_set`);
-- 
-- update gyms set blueprint = ST_GeomFromText('POLYGON((0 0,1.6278368994281855 0.2765634732161366,2.7054272241422783 3.664299480953304,3.870908173856331 5.903981272926622,8.00176754885633 6.1661915649461525,9.75958004885633 4.3283033167892055,10.81426754885633 1.6076056210529026,13.71465817385633 3.451430446891489,14.41778317385633 8.258755871337721,17.054501923856332 10.858630713832587,21.888486298856332 10.772301330887231,25.84356442385633 10.08079100378647,28.12872067385633 11.634450116311246,28.74395504885633 14.459650178229145,29.71075192385633 16.997401630681374,32.87481442385633 18.42069603003528,38.14825192385633 17.33330391100316,45.09161129885633 17.165428806555745,46.23418942385633 19,0.3552831738563311 19,0 0))') where gym_id=1