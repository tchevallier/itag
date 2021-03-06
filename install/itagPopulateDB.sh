#!/bin/bash
#
# iTag
#
#  Automatically tag a geographical footprint against every kind of things
# (i.e. Land Cover, OSM data, population count, etc.)
#
# jerome[dot]gasperi[at]gmail[dot]com
#  
#  
#  This software is governed by the CeCILL-B license under French law and
#  abiding by the rules of distribution of free software.  You can  use,
#  modify and/ or redistribute the software under the terms of the CeCILL-B
#  license as circulated by CEA, CNRS and INRIA at the following URL
#  "http://www.cecill.info".
# 
#  As a counterpart to the access to the source code and  rights to copy,
#  modify and redistribute granted by the license, users are provided only
#  with a limited warranty  and the software's author,  the holder of the
#  economic rights,  and the successive licensors  have only  limited
#  liability.
# 
#  In this respect, the user's attention is drawn to the risks associated
#  with loading,  using,  modifying and/or developing or reproducing the
#  software by the user in light of its specific status of free software,
#  that may mean  that it is complicated to manipulate,  and  that  also
#  therefore means  that it is reserved for developers  and  experienced
#  professionals having in-depth computer knowledge. Users are therefore
#  encouraged to load and test the software's suitability as regards their
#  requirements in conditions enabling the security of their systems and/or
#  data to be ensured and,  more generally, to use and operate it in the
#  same conditions as regards security.
# 
#  The fact that you are presently reading this means that you have had
#  knowledge of the CeCILL-B license and that you accept its terms.
#  

# Paths are mandatory from command line
SUPERUSER=postgres
DB=itag
USER=itag
usage="## iTag populate installation\n\n  Usage $0 -D <data directory> [-d <database name> -s <database SUPERUSER> -u <database USER> -F]\n\n  -D : absolute path to the data directory containing countries,continents,etc.\n  -s : database SUPERUSER (default "postgres")\n  -u : database USER (default "itag")\n  -d : database nam (default "itag")\n"
while getopts "D:d:s:u:hF" options; do
    case $options in
        D ) DATADIR=`echo $OPTARG`;;
        d ) DB=`echo $OPTARG`;;
        u ) USER=`echo $OPTARG`;;
        s ) SUPERUSER=`echo $OPTARG`;;
        h ) echo -e $usage;;
        \? ) echo -e $usage
            exit 1;;
        * ) echo -e $usage
            exit 1;;
    esac
done
if [ "$DATADIR" = "" ]
then
    echo -e $usage
    exit 1
fi

# ================== POLITICAL =====================
## Insert Continents
shp2pgsql -g geom -d -W LATIN1 -s 4326 -I $DATADIR/political/continents/continent.shp continents | psql -d $DB -U $SUPERUSER
psql -d itag  -U $SUPERUSER << EOF
CREATE INDEX idx_continents_name ON public.continents (continent);
EOF

## Insert Countries
shp2pgsql -g geom -d -W LATIN1 -s 4326 -I $DATADIR/political/countries/ne_110m_admin_0_countries.shp countries | psql -d $DB -U $SUPERUSER
psql -d $DB  -U $SUPERUSER << EOF
--
-- This is for WorldCountries not for ne_110m_admin_0_countries
-- UPDATE countries set name='Congo' WHERE iso_3166_3='ZAR';
-- UPDATE countries set name='Macedonia' WHERE iso_3166_3='MKD';
--
-- Optimisation : predetermine continent for each country
-- ALTER TABLE countries ADD COLUMN continent VARCHAR(13);
-- UPDATE countries SET continent = (SELECT continent FROM continents WHERE st_intersects(continents.geom, countries.geom) LIMIT 1);
--
UPDATE countries set name='Bosnia and Herzegovina' WHERE iso_a3 = 'BIH';
UPDATE countries set name='Central African Republic' WHERE iso_a3 = 'CAF';
UPDATE countries set name='Czech Republic' WHERE iso_a3 = 'CZE';
UPDATE countries set name='Congo' WHERE iso_a3 = 'COD';
UPDATE countries set name='North Korea' WHERE iso_a3 = 'PRK';
UPDATE countries set name='Dominican Republic' WHERE iso_a3 = 'DOM';
UPDATE countries set name='Equatorial Guinea' WHERE iso_a3 = 'GNQ';
UPDATE countries set name='Falkland Islands' WHERE iso_a3 = 'FLK';
UPDATE countries set name='French Southern and Antarctic Lands' WHERE iso_a3 = 'ATF';
UPDATE countries set name='Northern Cyprus' WHERE name = 'N. Cyprus';
UPDATE countries set name='South Sudan' WHERE iso_a3 = 'SSD';
UPDATE countries set name='Solomon Islands' WHERE iso_a3 = 'SLB';
UPDATE countries set name='Western Sahara' WHERE iso_a3 = 'ESH';
UPDATE countries set name='Ivory Coast' WHERE iso_a3 = 'CIV';
UPDATE countries set name='Laos' WHERE iso_a3 = 'LAO';

CREATE INDEX idx_countries_name ON public.countries (name);
CREATE INDEX idx_countries_geom ON public.countries USING gist(geom);
EOF

## Insert Cities
shp2pgsql -g geom -d -W LATIN1 -s 4326 -I $DATADIR/political/cities/cities.shp cities | psql -d $DB -U $SUPERUSER
psql -d $DB -U $SUPERUSER << EOF
UPDATE cities set country='The Gambia' WHERE country='Gambia';
CREATE INDEX idx_cities_name ON public.cities (name);
EOF

## Insert Cities from Geonames
# See https://github.com/colemanm/gazetteer/blob/master/docs/geonames_postgis_import.md
psql -d $DB -U $SUPERUSER << EOF
CREATE TABLE geoname (
    geonameid   int,
    name varchar(200),
    asciiname varchar(200),
    alternatenames varchar(8000),
    latitude float,
    longitude float,
    fclass char(1),
    fcode varchar(10),
    country varchar(2),
    cc2 varchar(60),
    admin1 varchar(20),
    admin2 varchar(80),
    admin3 varchar(20),
    admin4 varchar(20),
    population bigint,
    elevation int,
    gtopo30 int,
    timezone varchar(40),
    moddate date
 );
SET client_encoding = 'UTF8'; 
COPY geoname (geonameid,name,asciiname,alternatenames,latitude,longitude,fclass,fcode,country,cc2,admin1,admin2,admin3,admin4,population,elevation,gtopo30,timezone,moddate) FROM '$DATADIR/geonames/cities1000.txt' NULL AS '';
ALTER TABLE ONLY geoname ADD CONSTRAINT pk_geonameid PRIMARY KEY (geonameid);
SELECT AddGeometryColumn ('public','geoname','geom',4326,'POINT',2);
UPDATE geoname SET geom = ST_PointFromText('POINT(' || longitude || ' ' || latitude || ')', 4326);
CREATE INDEX idx_geoname_geom ON public.geoname USING gist(geom);
CREATE INDEX idx_geoname_name ON public.geoname (name);
ALTER TABLE geoname ADD COLUMN searchname VARCHAR(200);
UPDATE geoname SET searchname = lower(replace(replace(asciiname, '-', ''), ' ', ''));
UPDATE geoname SET searchname = replace(searchname, '\`', '');
CREATE INDEX idx_geoname_searchname ON public.geoname (searchname);
ALTER TABLE geoname ADD COLUMN countryname VARCHAR(200);
UPDATE geoname SET countryname=(SELECT name FROM countries WHERE geoname.country = countries.iso_a2 LIMIT 1);
CREATE INDEX idx_geoname_countryname ON public.geoname ((lower(countryname)));
EOF

## French departments
shp2pgsql -g geom -d -W LATIN1 -s 4326 -I $DATADIR/political/france/deptsfrance.shp deptsfrance | psql -d $DB -U $SUPERUSER
psql -d $DB -U $SUPERUSER << EOF
UPDATE deptsfrance set nom_dept=initcap(nom_dept);
UPDATE deptsfrance set nom_dept=replace(nom_dept, '-De-', '-de-');
UPDATE deptsfrance set nom_dept=replace(nom_dept, ' De ', ' de ');
UPDATE deptsfrance set nom_dept=replace(nom_dept, 'D''', 'd''');
UPDATE deptsfrance set nom_dept=replace(nom_dept, '-Et-', '-et-');
UPDATE deptsfrance set nom_region=initcap(nom_region);
UPDATE deptsfrance set nom_region='Ile-de-France' WHERE nom_region='Ile-De-France';
UPDATE deptsfrance set nom_region='Nord-Pas-de-Calais' WHERE nom_region='Nord-Pas-De-Calais';
UPDATE deptsfrance set nom_region='Pays de la Loire' WHERE nom_region='Pays De La Loire';
UPDATE deptsfrance set nom_region='Provence-Alpes-Cote d''Azur' WHERE nom_region='Provence-Alpes-Cote D''Azur';
CREATE INDEX idx_deptsfrance_dept ON public.deptsfrance (nom_dept);
CREATE INDEX idx_deptsfrance_region ON public.deptsfrance (nom_region);
EOF

# =================== GEOPHYSICAL ==================
## Insert plates
shp2pgsql -g geom -d -W LATIN1 -s 4326 -I $DATADIR/geophysical/plates/plates.shp plates | psql -d $DB -U $SUPERUSER

## Insert faults
shp2pgsql -g geom -d -W LATIN1 -s 4326 -I $DATADIR/geophysical/faults/FAULTS.SHP faults | psql -d $DB -U $SUPERUSER
psql -d $DB  -U $SUPERUSER << EOF
DELETE FROM faults WHERE type IS NULL;
UPDATE faults set type='Thrust fault' WHERE type='thrust-fault';
UPDATE faults set type='step' WHERE type='Step';
UPDATE faults set type='Tectonic Contact' WHERE type='tectonic contact';
UPDATE faults set type='Rift' WHERE type='rift';
EOF

## Insert volcanoes
shp2pgsql -g geom -d -W LATIN1 -s 4326 -I $DATADIR/geophysical/volcanoes/VOLCANO.SHP volcanoes | psql -d $DB -U $SUPERUSER

# ===== UNUSUED ======
## Insert glaciers
shp2pgsql -g geom -d -W LATIN1 -s 4326 -I $DATADIR/geophysical/glaciers/Glacier.shp glaciers | psql -d $DB -U $SUPERUSER
// DOWNLOAD THIS INSTEAD - http://nsidc.org/data/docs/noaa/g01130_glacier_inventory/#data_descriptions

## Major earthquakes since 1900
shp2pgsql -g geom -d -W LATIN1 -s 4326 -I $DATADIR/geophysical/earthquakes/MajorEarthquakes.shp earthquakes | psql -d $DB -U $SUPERUSER
 

# ==================== AMENITIES ===================== 
## Insert airport
shp2pgsql -g geom -d -W LATIN1 -s 4326 -I $DATADIR/amenities/airports/export_airports.shp airports | psql -d $DB -U $SUPERUSER

# ==================== LANDCOVER =====================
psql -U $SUPERUSER -d $DB << EOF
CREATE TABLE landcover (
    ogc_fid         SERIAL,
    dn              INTEGER
);
SELECT AddGeometryColumn ('public','landcover','wkb_geometry',4326,'POLYGON',2);
CREATE INDEX landcover_geometry_idx ON landcover USING gist (wkb_geometry);
EOF

# GRANT RIGHTS TO itag USER
psql -U $SUPERUSER -d $DB << EOF
GRANT SELECT on airports to $USER;
GRANT SELECT on cities to $USER;
GRANT SELECT on geoname to $USER;
GRANT SELECT on deptsfrance to $USER;
GRANT SELECT on continents to $USER;
GRANT SELECT on countries to $USER;
GRANT SELECT on earthquakes to $USER;
GRANT SELECT on glaciers to $USER;
GRANT SELECT on plates to $USER;
GRANT SELECT on faults to $USER;
GRANT SELECT on volcanoes to $USER;
GRANT SELECT on landcover to $USER;
EOF