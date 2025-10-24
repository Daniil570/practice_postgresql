/*ЗАДАНИЕ 3.1*/

/*Создаем два столбца: 1.Количество строк в определенной ячейке. 
 * 2.Количество уникальных значений
 * Изначально было 7297 строк, одна из которых полностью состоит из null*/
SELECT 
  COUNT(*) AS total_rows,
  COUNT(DISTINCT "data.general.id") AS distinct_values
FROM culture_data.culture_palaces_clubs;

/*Проверка на пустые ячейки в столбце*/
SELECT COUNT(*) AS null_count
FROM culture_data.culture_palaces_clubs
WHERE "data.general.id" IS NULL;

/*Просмотр строки, в котором присутствует null*/
SELECT *
FROM culture_data.culture_palaces_clubs
WHERE "data.general.id" IS NULL;

/*После того, как мы написали прошлый запрос и увидели,
 *  что все строки пустые, мы спокойно можем данную строку удалить*/
DELETE FROM culture_data.culture_palaces_clubs
WHERE "data.general.id" IS NULL;

/*Добавление первичного ключа для уникальной колонки*/
ALTER TABLE culture_data.culture_palaces_clubs
ADD CONSTRAINT pk_culture_palaces_clubs PRIMARY KEY ("data.general.id");

/*Создание счетчика последовательности Sequence.
 * Начинается с 1, последующие будут на +1 больше, без мин и макс значения.
 * Кеширование на всякий случай, чтобы при сбое СУБД небыло пропусков в последовательности*/
CREATE SEQUENCE culture_data.culture_palaces_clubs_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

/*Подключаем sequence к нужной колонке*/
ALTER TABLE culture_data.culture_palaces_clubs
ALTER COLUMN "data.general.id" SET DEFAULT nextval('culture_data.culture_palaces_clubs_seq');



/*ЗАДАНИЕ 3.2*/


/*Добавление NOT NULL*/
ALTER TABLE culture_data.culture_palaces_clubs
ALTER COLUMN "data.general.name" SET NOT NULL,
ALTER COLUMN "data.general.address.fullAddress" SET NOT NULL,
ALTER COLUMN "data.general.description" SET NOT NULL,
ALTER COLUMN "data.general.category.name" SET NOT NULL;

/*Проверка дубликатов для создания UNIQUE*/
SELECT "data.general.externalInfo", COUNT(*)
FROM culture_data.culture_palaces_clubs
GROUP BY "data.general.externalInfo"
HAVING COUNT(*) > 1;

/*Добавление UNIQUE*/
ALTER TABLE culture_data.culture_palaces_clubs
ADD CONSTRAINT unique_externalInfo UNIQUE ("data.general.externalInfo");



/*ЗАДАНИЕ 3.3*/


/*Удаление всех записей, которые не относятся к Вологодской области*/
SELECT *
from culture_data.culture_palaces_clubs 
WHERE "data.general.address.fullAddress" NOT ILIKE '%Вологодская%';


/*Скачивание расширения postgis*/
CREATE EXTENSION IF NOT EXISTS postgis schema culture_data;

/*Делаем PostGIS-функции доступными в текущей схеме*/ 
SET search_path = culture_data;

/*Проверка, что все работает*/
SELECT PostGIS_Version();



/*Добавление колонки geom с определенным типом данных*/
ALTER TABLE culture_data.culture_palaces_clubs
ADD COLUMN IF NOT EXISTS geom geometry(Point, 4326);


/*Преобразование данных из колонки data.general.address.mapPosition в
 *геометрию типа Point с использованием функции ST_GeomFromGeoJSON и
 *перенесение их в новую колонку geom.*/
UPDATE culture_data.culture_palaces_clubs
SET geom = ST_SetSRID(
    ST_GeomFromGeoJSON("data.general.address.mapPosition"::text),
    4326
)
WHERE "data.general.address.mapPosition" IS NOT NULL;


/* Проверка создания геометрии */
SELECT 
    "data.general.id", 
    ST_AsText(geom) AS geom_coordinates
FROM 
    culture_data.culture_palaces_clubs
LIMIT 10;

/*Добавляем физическую колонку id*/
ALTER TABLE culture_data.culture_palaces_clubs
ADD COLUMN IF NOT EXISTS id BIGINT;

/* Переносим значения из JSON data.general.id */
UPDATE culture_data.culture_palaces_clubs
SET id = ("data.general.id")::BIGINT
WHERE id IS NULL;

/* Добавляем ограничение уникальности или первичный ключ */
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'unique_club_id'
    ) THEN
        ALTER TABLE culture_data.culture_palaces_clubs
        ADD CONSTRAINT unique_club_id UNIQUE (id);
    END IF;
END $$;

/* Сначала создаём sequence */
CREATE SEQUENCE IF NOT EXISTS culture_data.tags_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

/* Теперь создаём таблицу tags */
CREATE TABLE IF NOT EXISTS culture_data.tags (
    id BIGINT PRIMARY KEY DEFAULT nextval('culture_data.tags_seq'), 
    tag_name TEXT NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

/* Переносим уникальные теги из JSON-массива */
INSERT INTO culture_data.tags (tag_name)
SELECT DISTINCT jsonb_array_elements_text("data.general.tags") AS tag
FROM culture_data.culture_palaces_clubs
WHERE "data.general.tags" IS NOT NULL
  AND jsonb_typeof("data.general.tags") = 'array'
ON CONFLICT (tag_name) DO NOTHING;

/* Проверяем, что всё корректно */
SELECT COUNT(*) AS total_tags, COUNT(DISTINCT tag_name) AS unique_tags
FROM culture_data.tags;

/*Более тщательная проверка, будут видны 10 строк*/
SELECT * FROM culture_data.tags LIMIT 10;

/*Создаем связь многие ко многим между нужными таблицами*/
CREATE TABLE IF NOT EXISTS culture_data.m2m_culture_palaces_clubs_tags (
    club_id BIGINT REFERENCES culture_data.culture_palaces_clubs(id) ON DELETE CASCADE,
    tag_id  BIGINT REFERENCES culture_data.tags(id) ON DELETE CASCADE,
    PRIMARY KEY (club_id, tag_id)
);

/*Заполняем таблицу связями клуб и тег. Чтобы не повторялось club и tag id,
 * я их сократил до одной буквы, чтобы в последующей работе не было ошибок при запросах.
 * Все это делается для того, так как у нас есть первичные ключи с такими названиями в 
 * одной из таблиц*/
INSERT INTO culture_data.m2m_culture_palaces_clubs_tags (club_id, tag_id)
SELECT DISTINCT c.id, t.id
FROM culture_data.culture_palaces_clubs c
JOIN LATERAL jsonb_array_elements_text(c."data.general.tags") AS tag_json(tag) ON TRUE
JOIN culture_data.tags t ON t.tag_name = tag_json.tag
WHERE c."data.general.tags" IS NOT NULL;

/*Создаём индексы для ускорения запросов*/
CREATE INDEX IF NOT EXISTS idx_m2m_club_id ON culture_data.m2m_culture_palaces_clubs_tags (club_id);
CREATE INDEX IF NOT EXISTS idx_m2m_tag_id  ON culture_data.m2m_culture_palaces_clubs_tags (tag_id);

/*Проверяем результат*/
SELECT COUNT(*) AS total_links FROM culture_data.m2m_culture_palaces_clubs_tags;

/*Проверяем более тщательно, будут видны 10 строк*/
SELECT 
    c.id AS club_id,
    c."data.general.name" AS club_name,
    t.tag_name
FROM culture_data.m2m_culture_palaces_clubs_tags m
JOIN culture_data.culture_palaces_clubs c ON m.club_id = c.id
JOIN culture_data.tags t ON m.tag_id = t.id
LIMIT 10;


