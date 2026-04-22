-- ============================================================
-- PROYECTO: People Analytics 
-- AUTOR: Jorge Torres
-- FECHA: Abril 2026
-- DESCRIPCIÓN: Análisis del estado de la plantilla para apoyar
--              la planificación anual de RRHH
-- TÉCNICAS: Window Functions, CTEs, PIVOT con CASE WHEN, ROW_NUMBER
-- ============================================================

-- ============================================================
-- PREGUNTA 1: ¿Cómo está distribuida la plantilla?
-- MÉTRICAS: Headcount por departamento, % sobre total
-- TABLAS: EmployeeDepartmentHistory, Department
-- TÉCNICA: SUM OVER() para porcentaje global sin subquery
-- Hallazgo: Production concentra el 61.72% de la plantilla
-- ============================================================

SELECT
	Name AS departamento,
	COUNT(BusinessEntityID) AS num_empleados,
	CAST(
		COUNT(BusinessEntityID) * 1.0 / 
		SUM(COUNT(BusinessEntityID)) OVER() * 100 
	AS DECIMAL (5,2)) AS pct_total 
FROM
	HumanResources.EmployeeDepartmentHistory AS dh
INNER JOIN
	HumanResources.Department AS d
		ON dh.DepartmentID = d.DepartmentID
WHERE
	EndDate IS NULL
GROUP BY
	Name
ORDER BY
	COUNT(BusinessEntityID) DESC;

-- ============================================================
-- PREGUNTA 2: ¿Cuál es la antigüedad media por departamento?
-- MÉTRICAS: Años de antigüedad media
-- TABLAS: Employee, EmployeeDepartmentHistory, Department
-- NOTA: Se usa DATEDIFF(DAY) / 365.25 para mayor precisión que DATEDIFF(YEAR)
-- Hallazgo: Engineering y Shipping lideran con 17.26 años de media
--           Sales es el departamento más nuevo con 14.34 años
-- ============================================================

SELECT
	Name AS departamento,
	CAST(
		AVG(DATEDIFF(DAY, HireDate, GETDATE()) / 365.25) 
	AS DECIMAL (5,2)) AS avg_antiguedad
FROM
	HumanResources.Employee AS e
LEFT JOIN
	HumanResources.EmployeeDepartmentHistory AS dh
		ON e.BusinessEntityID = dh.BusinessEntityID 
LEFT JOIN
	HumanResources.Department AS d
		ON dh.DepartmentID = d.DepartmentID
WHERE
	EndDate IS NULL
GROUP BY
	Name
ORDER BY
	AVG(DATEDIFF(DAY, HireDate, GETDATE()) / 365.25) DESC;

-- ============================================================
-- PREGUNTA 3: ¿Cuál es la masa salarial mensual por departamento?
-- MÉTRICAS: Masa salarial mensual, % sobre total
-- TABLAS: EmployeePayHistory, EmployeeDepartmentHistory, Department
-- TÉCNICA: ROW_NUMBER para quedarse con el salario más reciente de cada empleado
-- NOTA: Rate es tarifa por hora — se multiplica por 8h/día y 22 días/mes
-- Hallazgo: Production concentra el 48% de la masa salarial total ($445,805/mes)
--           Sales tiene el 10% de masa salarial con solo el 6% del headcount
-- ============================================================

WITH salario_reciente AS (
	SELECT
		BusinessEntityID,
		Rate,
		ROW_NUMBER() OVER(
			PARTITION BY BusinessEntityID
			ORDER BY RateChangeDate DESC
		) AS rn
	FROM
		HumanResources.EmployeePayHistory 
),

masa_salarial AS (

SELECT
	d.Name AS department,
	(SUM(sr.rate) * 8 * 22)  AS masa_salarial_mensual
FROM 
	salario_reciente AS sr
INNER JOIN	
	HumanResources.EmployeeDepartmentHistory AS dh
		ON sr.BusinessEntityID = dh.BusinessEntityID
INNER JOIN	
	HumanResources.Department AS d
		ON dh.DepartmentID = d.DepartmentID
WHERE 
	sr.rn = 1 AND
	dh.EndDate IS NULL
GROUP BY 
	d.Name
)

SELECT
	department,
	CAST(
		masa_salarial_mensual 
	AS DECIMAL (10,2)) AS masa_salarial,
	masa_salarial_mensual / SUM(masa_salarial_mensual) OVER() * 100 AS pct_total
FROM
	masa_salarial
ORDER BY
	masa_salarial_mensual DESC;

-- ============================================================
-- PREGUNTA 4: ¿Existe brecha salarial entre géneros?
-- MÉTRICAS: Salario medio por género, brecha absoluta
-- TABLAS: EmployeePayHistory, Employee, EmployeeDepartmentHistory, Department
-- TÉCNICA: PIVOT con AVG(CASE WHEN Gender = 'F/M' THEN salario END)
-- Hallazgo: Executive tiene la mayor brecha a favor de hombres ($11,511/mes)
--           Engineering y Human Resources tienen brecha a favor de mujeres
--           NULL en Production Control y Quality Assurance — solo un género
-- ============================================================

WITH salario_reciente AS (
	SELECT
		BusinessEntityID,
		Rate,
		ROW_NUMBER() OVER(
			PARTITION BY BusinessEntityID
			ORDER BY RateChangeDate DESC
		) AS rn
	FROM
		HumanResources.EmployeePayHistory 
)

SELECT
	Name AS departamento,
	AVG(CASE WHEN e.Gender = 'M' THEN sr.Rate * 8 * 22 END) AS salario_medio_M,
	AVG(CASE WHEN e.Gender = 'F' THEN sr.Rate * 8 * 22 END) AS salario_medio_F,

	AVG(CASE WHEN e.Gender = 'F' THEN sr.Rate * 8 * 22 END) -
	AVG(CASE WHEN e.Gender = 'M' THEN sr.Rate * 8 * 22 END) AS brecha
FROM
	salario_reciente AS sr
INNER JOIN
	HumanResources.Employee AS e
		ON sr.BusinessEntityID = e.BusinessEntityID 
INNER JOIN
	HumanResources.EmployeeDepartmentHistory AS dh
		ON e.BusinessEntityID = dh.BusinessEntityID
INNER JOIN
	HumanResources.Department AS d
		ON dh.DepartmentID = d.DepartmentID
WHERE 
	rn = 1 AND
	EndDate IS NULL
GROUP BY
	d.Name;

-- ============================================================
-- PREGUNTA 5: ¿Cuál es la tasa de rotación histórica?
-- MÉTRICAS: Bajas históricas, total histórico, tasa de rotación %
-- TABLAS: EmployeeDepartmentHistory, Department
-- TÉCNICA: Dos CTEs — histórico total y bajas — unidas con JOIN
-- NOTA: EndDate IS NOT NULL indica que el empleado salió del departamento
-- Hallazgo: Engineering y Quality Assurance lideran con 14.29% de rotación
--           La rotación general es muy baja — datos de BD de ejemplo
-- ============================================================

WITH historico AS (
	SELECT
		Name AS departamento,
		COUNT(BusinessEntityID) AS total_historico
	FROM
		HumanResources.EmployeeDepartmentHistory AS dh
	INNER JOIN
		HumanResources.Department AS d
			ON dh.DepartmentID = d.DepartmentID
	GROUP BY
		d.Name
),

bajas AS (
	SELECT
		d.Name AS departamento,
		COUNT(BusinessEntityID) AS bajas
	FROM 
		HumanResources.EmployeeDepartmentHistory AS dh
    INNER JOIN 
		HumanResources.Department AS d
			ON dh.DepartmentID = d.DepartmentID
	WHERE 
		EndDate IS NOT NULL
	GROUP BY
		d.Name
)

SELECT
	b.departamento,
	h.total_historico,
	b.bajas,
	CAST(
		(b.bajas * 1.0) / h.total_historico * 100 
		AS DECIMAL (5,2)) AS tasa_rotacion
FROM
	historico AS h
INNER JOIN
	bajas AS b 
		ON h.departamento = b.departamento
ORDER BY
	tasa_rotacion DESC

-- ============================================================
-- PREGUNTA 6: ¿Cuál es el perfil de edad de la plantilla?
-- MÉTRICAS: Edad media por departamento, distribución por tramos
-- TABLAS: Employee, EmployeeDepartmentHistory, Department
-- NOTA: Se separa en dos queries — edad media por departamento
--       y distribución individual por tramos (Junior/Mid/Senior)
-- Hallazgo: 56.21% Senior (>45 años), 43.79% Mid (30-45), 0% Junior
--           Engineering tiene la edad media más alta con 59.75 años
--           Riesgo de jubilaciones en cadena en los próximos años
-- ============================================================
--6A
WITH edad_media AS (
	SELECT
		Name AS departamento,
		CAST(
			AVG(DATEDIFF(DAY, BirthDate, GETDATE()) / 365.25) 
			AS DECIMAL (5,2))AS edad_media_dept
	FROM 
		HumanResources.Employee AS e
	INNER JOIN
		HumanResources.EmployeeDepartmentHistory AS dh
			ON e.BusinessEntityID = dh.BusinessEntityID
	INNER JOIN
		HumanResources.Department AS d
			ON dh.DepartmentID = d.DepartmentID
	WHERE 
		EndDate IS NULL
	GROUP BY
		Name
)

SELECT
	departamento,
	edad_media_dept,
	CASE	
		WHEN edad_media_dept < 30 THEN 'Junior'
		WHEN edad_media_dept BETWEEN 30 AND 45 THEN 'Mid'
		ELSE 'Senior'
	END AS distribucion_edad
FROM 
	edad_media
ORDER BY
	edad_media_dept DESC;

GO
--6B
WITH clasificacion AS (
    SELECT
        e.BusinessEntityID,
        DATEDIFF(DAY, e.BirthDate, GETDATE()) / 365.25 AS edad,
        CASE
            WHEN DATEDIFF(DAY, e.BirthDate, GETDATE()) / 365.25 < 30 THEN 'Junior'
            WHEN DATEDIFF(DAY, e.BirthDate, GETDATE()) / 365.25 BETWEEN 30 AND 45 THEN 'Mid'
            ELSE 'Senior'
        END AS tramo
    FROM 
		HumanResources.Employee AS e
    INNER JOIN 
		HumanResources.EmployeeDepartmentHistory AS dh
			ON e.BusinessEntityID = dh.BusinessEntityID
    WHERE dh.EndDate IS NULL
)
SELECT
    tramo,
    COUNT(*) AS num_empleados,
    CAST(COUNT(*) * 1.0 / SUM(COUNT(*)) OVER() * 100 AS DECIMAL(5,2)) AS pct_total
FROM 
	clasificacion
GROUP BY 
	tramo
ORDER BY 
	num_empleados DESC;

-- ============================================================
-- PREGUNTA 7: ¿Qué empleados llevan más tiempo en la empresa?
-- MÉTRICAS: Antigüedad en años, salario actual mensual
-- TABLAS: EmployeePayHistory, Employee, Person
-- TÉCNICA: ROW_NUMBER para salario más reciente + TOP 10 por antigüedad
-- Hallazgo: Guy Gilbert es el empleado más antiguo con 19.78 años
--           La antigüedad no está correlacionada con el salario —
--           Guy Gilbert cobra $2,191 siendo el más veterano
-- ============================================================

WITH salario_reciente AS (
	SELECT
		BusinessEntityID,
		Rate,
		ROW_NUMBER() OVER(
			PARTITION BY BusinessEntityID
			ORDER BY RateChangeDate DESC
		) AS rn
	FROM
		HumanResources.EmployeePayHistory 
)

SELECT TOP 10 
	e.JobTitle AS titulo_trabajo,
	CONCAT(FirstName, ' ', LastName) AS nombre_completo,
	HireDate AS fecha_contratacion,
	CAST(
		DATEDIFF(DAY, HireDate, GETDATE()) / 365.25
	AS DECIMAL (5,2)) AS antiguedad,
	CAST(
		(r.Rate * 8 * 22) 
	AS DECIMAL (10,2)) AS salario_actual
FROM
	salario_reciente AS r
INNER JOIN
	HumanResources.Employee AS e
		ON r.BusinessEntityID = e.BusinessEntityID
INNER JOIN
	Person.Person AS p
		ON e.BusinessEntityID = p.BusinessEntityID
WHERE 
	rn = 1
ORDER BY
	antiguedad DESC;
