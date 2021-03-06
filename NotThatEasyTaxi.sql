CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;


/***********************************************************************************
------------------------------------------------------------------------------------
-------------------------------DEFINICION DE TABLAS---------------------------------
------------------------------------------------------------------------------------
***********************************************************************************/
DROP TABLE IF EXISTS cliente CASCADE;
CREATE TABLE cliente(
	celular BIGINT PRIMARY KEY,
	contrasena TEXT NOT NULL,
	nombres VARCHAR(30) NOT NULL,
	apellidos VARCHAR(30) NOT NULL,
	genero CHAR(1) NOT NULL,
	tarjeta_credito BIGINT NOT NULL,
	direccion_residencia VARCHAR(20) NOT NULL
CHECK(genero IN ('M','F','N'))
);

DROP TABLE IF EXISTS taxi CASCADE;
CREATE TABLE taxi(
	placa CHAR(6) PRIMARY KEY,
	modelo VARCHAR(15) NOT NULL,
	marca VARCHAR(15) NOT NULL,
	baul CHAR(1) NOT NULL,
	ano INT NOT NULL,
	soat INT NOT NULL
CHECK(baul IN ('G','P','N'))
);

DROP TABLE IF EXISTS conductor CASCADE;
CREATE TABLE conductor(
	celular BIGINT PRIMARY KEY,
	contrasena TEXT NOT NULL,
	nombres VARCHAR(30) NOT NULL,
	apellidos VARCHAR(30) NOT NULL,
	genero CHAR(1) NOT NULL,
	placa CHAR(6) NOT NULL REFERENCES taxi(placa),
	disponibilidad BOOL,
	posicion_actual GEOGRAPHY(POINT)
CHECK(genero IN ('M','F','N'))
);

DROP TABLE IF EXISTS posicion CASCADE;
CREATE TABLE posicion(
	id_pos GEOGRAPHY(POINT) PRIMARY KEY,
	direccion TEXT
);

DROP TABLE IF EXISTS viajes CASCADE;
CREATE TABLE viajes(
	id_viaje SERIAL PRIMARY KEY,
	celular_cliente BIGINT REFERENCES cliente(celular),
	celular_conductor BIGINT NOT NULL REFERENCES conductor(celular),
	id_pos_origen GEOGRAPHY(POINT) NOT NULL REFERENCES posicion(id_pos),
	id_pos_destino GEOGRAPHY(POINT) NOT NULL REFERENCES posicion(id_pos),
	fecha DATE NOT NULL,
	pagado BOOL NOT NULL,
	calificacion INT NOT NULL
);

DROP TABLE IF EXISTS  Conductor_Viajes CASCADE;
CREATE TABLE Conductor_Viajes(
	id_viaje SERIAL PRIMARY KEY,
	celular_conductor BIGINT NOT NULL REFERENCES conductor(celular),
	cobrado BOOL NOT NULL
);

DROP TABLE IF EXISTS favoritos CASCADE;
CREATE TABLE favoritos(
	celular BIGINT NOT NULL REFERENCES cliente(celular),
	id_pos GEOGRAPHY(POINT) NOT NULL REFERENCES posicion(id_pos)
);
/***********************************************************************************
------------------------------------------------------------------------------------
-------------------------------DEFINICION DE INDICES---------------------------------
------------------------------------------------------------------------------------
***********************************************************************************/
--Indice para la tabla cliente
create index indiceCliente on cliente using hash (celular);

--Indice para la tabla conductor
create index indiceConductor on conductor using hash (celular);

--Indice para la tabla taxi
create index indiceTaxi on taxi using hash (placa);

--Indice para la tabla posicion
create index indicePosicion on posicion using hash (ST_ASTEXT(id_pos));

--Indice para la tabla viajes
create index indiceViajesCliente on viajes using hash (celular_cliente);
create index indiceViajesConductor on viajes using hash(celular_conductor);

--Indice para la tabla Conductor_Viajes
create index indiceConductor_Viajes on Conductor_Viajes using hash (celular_conductor);

--Indice para la tabla favoritos
create index indiceFavoritos on favoritos using hash (celular);


/***********************************************************************************
------------------------------------------------------------------------------------
-------------------------------FUNCIONES Y DISPARADORES-----------------------------
------------------------------------------------------------------------------------
************************************************************************************/

--Calcula la distancia entre dos puntos 
CREATE OR REPLACE FUNCTION distancia(TEXT,TEXT) RETURNS FLOAT AS $$
DECLARE
	pos1 ALIAS FOR $1;
	pos2 ALIAS FOR $2;
BEGIN
	RETURN ST_DISTANCESPHERE(pos1,pos2)/1000;
END;
$$ LANGUAGE plpgsql;


--Encuentra el celular del conductor mas cercano al punto dado
CREATE OR REPLACE FUNCTION hallarConductor(TEXT) RETURNS BIGINT AS $$
DECLARE
	pos ALIAS FOR $1;
	cel BIGINT;
BEGIN
	cel = (SELECT DISTINCT conductor.celular FROM conductor 
				WHERE ST_DistanceSphere(pos,ST_ASTEXT(conductor.posicion_actual)) = 
			(SELECT  min(ST_DISTANCESPHERE(pos,ST_ASTEXT(conductor.posicion_actual))) 
					FROM  conductor
					WHERE Conductor.disponibilidad=true));
	RETURN cel;
END;
$$ LANGUAGE plpgsql;

--Funcion para validar el login, retorna el tipo de usuario o una cadena vacia en caso de no ser un usuario valido
CREATE OR REPLACE FUNCTION login(BIGINT,TEXT) RETURNS TEXT AS $$
DECLARE
	cel ALIAS FOR $1;
	pass ALIAS FOR $2;
BEGIN
	IF EXISTS (SELECT * FROM cliente WHERE celular = cel and contrasena = crypt(pass,contrasena)) THEN
		RETURN 'Usuario';
	ELSIF EXISTS (SELECT * FROM conductor WHERE celular = cel and contrasena = crypt(pass,contrasena)) THEN
		RETURN 'Conductor';
	ELSE 
		RETURN ' ';
 	END IF;
END;
$$ LANGUAGE plpgsql;

--Funcion para insertar puntos que no estan insertados
CREATE OR REPLACE FUNCTION insertarPunto(GEOGRAPHY,TEXT) RETURNS BOOL AS $$
DECLARE
	pos ALIAS FOR $1;
	descripcion ALIAS FOR $2;
BEGIN
	IF EXISTS (SELECT * FROM posicion WHERE id_pos = pos) THEN
		RETURN false;
	ELSE 
		INSERT INTO posicion(id_pos,direccion) VALUES (pos,descripcion);
		RETURN true;
	END IF;
END;
$$ LANGUAGE plpgsql;

--Trigger  que agrega un viaje como no cobrado para el conductor que lo realizo
CREATE OR REPLACE FUNCTION insertarViaje() RETURNS TRIGGER AS $$
BEGIN

	INSERT INTO Conductor_Viajes(id_viaje,celular_conductor,cobrado) VALUES (NEW.id_viaje,NEW.celular_conductor,false);
	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS agregarViaje ON viajes;
CREATE TRIGGER agregarViaje AFTER INSERT ON viajes FOR EACH ROW EXECUTE PROCEDURE insertarViaje();

--Trigger que cambia la posicion de un conductor a el lugar de destino en el cual hizo el viaje
CREATE OR REPLACE FUNCTION cambiarPos() RETURNS TRIGGER AS $$
BEGIN
		UPDATE conductor
		SET posicion_actual = NEW.id_pos_destino
		WHERE celular = NEW.celular_conductor;
		RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS actualPosicion ON viajes;
CREATE TRIGGER actualPosicion AFTER INSERT ON viajes FOR EACH ROW EXECUTE PROCEDURE cambiarPos();

/***********************************************************************************
------------------------------------------------------------------------------------
---------------------------------------VISTAS---------------------------------------
------------------------------------------------------------------------------------
***********************************************************************************/

--Vista que relaciona cada conductor con la cantidad de kilometros que ha transportado
DROP VIEW IF EXISTS kmconductor;
CREATE VIEW kmconductor AS 
(Select celular as conductor,SUM(ST_DistanceSphere(ST_ASTEXT(id_pos_origen),ST_ASTEXT(id_pos_destino)))/1000 as km
from viajes right outer join conductor on conductor.celular=viajes.celular_conductor
	GROUP BY celular) ;


--Vista que relaciona cada cliente con la cantidad de kilometros que ha usado 
DROP VIEW IF EXISTS kmcliente;
CREATE VIEW kmcliente AS 
(Select celular as cliente, SUM(ST_DistanceSphere(ST_ASTEXT(id_pos_origen),ST_ASTEXT(id_pos_destino)))/1000 as km  
	from viajes right outer join cliente on cliente.celular=viajes.celular_cliente
	GROUP BY celular) ;


--Vista que relaciona cada conductor con la cantidad de kilometros que aun no ha cobrado
DROP VIEW IF EXISTS kmconductorCobrar;
CREATE VIEW kmconductorCobrar AS 
(Select celular as conductor,SUM(ST_DistanceSphere(ST_ASTEXT(id_pos_origen),ST_ASTEXT(id_pos_destino)))/1000 as km
from (viajes natural join conductor_viajes) right outer join conductor 
on conductor.celular=viajes.celular_conductor AND cobrado=false
	GROUP BY celular) ;


--Vista que relaciona cada cliente con la cantidad de kilometros que aun no ha pagado
DROP VIEW IF EXISTS kmclientePagar;
CREATE VIEW kmclientePagar AS 
(Select celular as cliente, SUM(ST_DistanceSphere(ST_ASTEXT(id_pos_origen),ST_ASTEXT(id_pos_destino)))/1000 as km  
	from viajes right outer join cliente on cliente.celular=viajes.celular_cliente and pagado=false
	GROUP BY celular) ;

--Vista que relaciona cada conductor con la cantidad de estrellas en promedio que tiene de sus viajes regiistrados
DROP VIEW IF EXISTS promestrellas;
CREATE VIEW promEstrellas AS (SELECT celular as celular,AVG(calificacion) as estrellas
FROM viajes right outer join conductor on viajes.celular_conductor=conductor.celular
GROUP BY celular);



/***********************************************************************************
------------------------------------------------------------------------------------
----------------------------USUARIOS DE LA BASE DE DATOS----------------------------
------------------------------------------------------------------------------------
***********************************************************************************/

--Usuario Cliente
DROP USER IF EXISTS usuario_clientes;
CREATE USER usuario_clientes WITH PASSWORD 'clients123';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO usuario_clientes;
GRANT INSERT ON cliente,posicion,viajes,favoritos TO usuario_clientes;
GRANT UPDATE ON cliente,viajes,favoritos TO usuario_clientes;

--Usuario Conductores
DROP USER IF EXISTS usuario_conductores;
CREATE USER usuario_conductores WITH PASSWORD 'drivers123';
GRANT SELECT ON taxi,conductor,posicion,viajes TO usuario_conductores;
GRANT INSERT ON taxi,conductor,posicion TO usuario_conductores;
GRANT UPDATE ON taxi,conductor,viajes TO usuario_conductores;
GRANT DELETE ON taxi TO usuario_conductores;

--Usuario para eliminar
DROP USER IF EXISTS alvaroUribe;
CREATE USER alvaroUribe WITH PASSWORD 'para-exterminar';
GRANT DELETE ON cliente,conductor TO alvaroUribe;

--Superusuario
DROP USER IF EXISTS super;
CREATE USER super WITH PASSWORD 'profe-paseme-en-5';
ALTER USER super SUPERUSER;


/***********************************************************************************
------------------------------------------------------------------------------------
----------------------INSERTANDO VALORES DE EJEMPLO---------------------------------
------------------------------------------------------------------------------------
***********************************************************************************/
INSERT INTO cliente VALUES (3222204261,crypt('1234', gen_salt('md5')),'Steban','Cadena','M',4341140110,'Cra 32b #41-53');
INSERT INTO cliente VALUES (1234567890,crypt('1234', gen_salt('md5')),'Steban','Cadena','M',4341140110,'Cra 32b #41-53');
INSERT INTO taxi VALUES ('ABC123','Nexo','Hyundai','G',2013,98422411);
INSERT INTO taxi VALUES ('CBA321','Nexo','Hyundai','P',2018,76352211);
INSERT INTO taxi VALUES ('VCB456','Nexo','Hyundai','P',2017,64312811);
INSERT INTO conductor VALUES (3218021197,crypt('1234', gen_salt('md5')),'Arjen','Granada','M','ABC123',true,'POINT(-76.516919 3.420180)');
INSERT INTO conductor VALUES (3456733214,crypt('1234', gen_salt('md5')),'Alex','Herrera','M','CBA321',false,'POINT(-76.530014 3.372059)');
INSERT INTO conductor VALUES (3127395835,crypt('1234', gen_salt('md5')),'Rosa','Cadena','F','VCB456',true,'POINT(-76.536722 3.442843)');
INSERT INTO posicion VALUES ('POINT(-76.502000 3.418842)','Diamante');
INSERT INTO posicion VALUES ('POINT(-76.530014 3.372059)','Univalle');
INSERT INTO posicion VALUES ('POINT(-76.545068 3.435787)','Parque del perro');
INSERT INTO posicion VALUES ('POINT(-76.516919 3.420180)','Animalario');
INSERT INTO posicion VALUES ('POINT(-76.536722 3.442843)','Loma de la cruz');
INSERT INTO favoritos VALUES (1234567890,'POINT(-76.502000 3.418842)');
INSERT INTO favoritos VALUES (1234567890,'POINT(-76.530014 3.372059)');
INSERT INTO favoritos VALUES (1234567890,'POINT(-76.545068 3.435787)');
INSERT INTO favoritos VALUES (1234567890,'POINT(-76.516919 3.420180)');
INSERT INTO viajes(celular_cliente,celular_conductor,id_pos_origen,id_pos_destino,fecha,pagado,calificacion) 
VALUES (3222204261,3456733214,'POINT(-76.502000 3.418842)','POINT(-76.530014 3.372059)',current_Date,false,1);
INSERT INTO viajes(celular_cliente,celular_conductor,id_pos_origen,id_pos_destino,fecha,pagado,calificacion) 
VALUES (3222204261,3456733214,'POINT(-76.502000 3.418842)','POINT(-76.545068 3.435787)',current_Date,false,2);
INSERT INTO viajes(celular_cliente,celular_conductor,id_pos_origen,id_pos_destino,fecha,pagado,calificacion) 
VALUES (3222204261,3456733214,'POINT(-76.545068 3.435787)','POINT(-76.502000 3.418842)',current_Date,false,3);

