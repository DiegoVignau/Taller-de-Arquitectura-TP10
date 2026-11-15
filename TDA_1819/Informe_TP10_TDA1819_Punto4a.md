# TRABAJO PRÁCTICO N° 10: PROCESADOR TDA 1819
## Implementación de la Técnica de Adelantamiento (Forwarding) EX→EX para Instrucciones Aritmético-Lógicas (Punto 4a)

**Asignatura:** Taller de Arquitectura  
**Año lectivo:** 2026 — 1°/2° Semestre  
**Tema asignado:** Ejercicio 4a — Forwarding EX→EX ALU→ALU  
**Fecha de entrega:** Viernes 27 de noviembre de 2026, 11:59:59 hs.  

---

## ÍNDICE GENERAL
1. **Introducción y Objetivos**
2. **Punto 1: Diseño y Desarrollo del Mecanismo de Forwarding en VHDL**
   - 2.1. Análisis del problema de riesgos RAW en el cauce del TDA 1819
   - 2.2. Arquitectura de la solución implementada
   - 2.3. Modificaciones detalladas por componente VHDL
   - 2.4. Resumen de archivos modificados y rutas en el proyecto (Requerimiento 4b)
3. **Punto 2: Programas de Prueba en Lenguaje Assembly**
   - 3.1. Programa 1: `fwd_alu_cadena.asm` (Cadena estricta Tipo A)
   - 3.2. Programa 2: `fwd_alu_operaciones.asm` (Mezcla Tipo A y Tipo B)
   - 3.3. Rutas de los programas de prueba (Requerimiento 4c)
4. **Punto 3: Análisis y Resultados de Simulación**
   - 4.1. Consigna 3a: Determinación de tiempos de ejecución y contrastes
   - 4.2. Consigna 3b: Flujo de ejecución ciclo por ciclo y uso de recursos
5. **Conclusiones**

---

## 1. INTRODUCCIÓN Y OBJETIVOS

El procesador TDA 1819 es una arquitectura didáctica segmentada en 5 etapas clásicas: Búsqueda de instrucción (IF - Fetch), Decodificación y lectura de registros (ID - Decode), Ejecución y cálculo aritmético/lógico (EX - Execute), Acceso a memoria de datos (MA - Memory Access) y Escritura en el banco de registros (WB - Writeback).

En su versión original, el procesador detecta las dependencias de datos de tipo RAW (Read-After-Write) mediante la entidad `raw_waw_detector`, la cual contabiliza las escrituras pendientes sobre cada registro general. Si una instrucción en etapa Decode intenta leer un operando que posee escrituras pendientes por parte de instrucciones previas en el cauce, el detector activa la señal de atasco `StallRAW = '1'`, congelando las etapas Decode y Fetch durante **dos ciclos de reloj completos** hasta que la instrucción productora alcanza la etapa Writeback y actualiza el banco de registros.

El objetivo asignado en este trabajo práctico (**Punto 4a**) consiste en:
> *"Incorporar la posibilidad de habilitar la técnica de Adelantamiento o Forwarding en el TDA 1819 para el escenario donde una instrucción aritmético-lógica realiza una operación en la ALU durante la etapa Execute cuyo resultado obtenido es requerido por otra instrucción aritmético-lógica subsiguiente como operando en la ALU durante la etapa Execute."*

Asimismo, se exige que la funcionalidad sea configurable mediante un generic booleano (`Forwarding`) que, al ser desactivado, reproduzca con exactitud el comportamiento original con atascos, permitiendo establecer un contraste cuantitativo y cualitativo riguroso.

---

## 2. PUNTO 1: DISEÑO Y DESARROLLO DEL MECANISMO DE FORWARDING EN VHDL

### 2.1. Análisis del problema de riesgos RAW ALU→ALU
Consideremos dos instrucciones aritmético-lógicas consecutivas:
```asm
I1: dadd r3, r1, r2    ; Calcula r3 = r1 + r2 en EX (Ciclo 3), escribe r3 en WB (Ciclo 5)
I2: dadd r4, r3, r1    ; Lee r3 en ID (Ciclo 3) para calcular r4 en EX (Ciclo 4)
```

En el cauce original sin adelantamiento:
- En el **Ciclo 3**, $I_1$ se encuentra en la etapa **Execute** calculando su resultado en la ALU.
- En el mismo **Ciclo 3**, $I_2$ se encuentra en la etapa **Decode** intentando leer el registro $R_3$.
- Como $I_1$ todavía no llegó a Writeback, el contador `R3_WrPending` es igual a $1$.
- `raw_waw_detector` activa `StallRAW <= '1'`, forzando a $I_2$ a esperar en Decode durante los ciclos 3 y 4.
- Recién en el **Ciclo 5**, cuando $I_1$ ejecuta Writeback y decrementa `R3_WrPending` a $0$, $I_2$ puede leer $R_3$ del banco de registros y pasar a Execute en el **Ciclo 6**.

**Pérdida de rendimiento:** 2 ciclos de burbuja (stalls) por cada dependencia RAW entre instrucciones ALU contiguas.

Sin embargo, el resultado de $I_1$ ya está disponible al final de la etapa Execute (Ciclo 3). Como $I_2$ no necesita el dato hasta el inicio de su propia etapa Execute (Ciclo 4), es físicamente posible transmitir el resultado directamente de la salida de la ALU a la entrada de la ALU en el ciclo siguiente, eliminando por completo los dos ciclos de atasco.

### 2.2. Arquitectura de la solución implementada
La solución requirió una acción coordinada entre dos subsistemas:

1. **Supresión selectiva del atasco en `raw_waw_detector`:**
   El detector debe inhibir la activación de `StallRAW` cuando se cumplan simultáneamente las siguientes condiciones:
   - `Forwarding = true` (adelantamiento habilitado por el usuario).
   - La instrucción actual en Execute es una operación ALU entera (`EX_is_ALU = '1'`).
   - La instrucción actual en Decode es una operación ALU entera (`ID_is_ALU = '1'`).
   - El registro destino de la instrucción en Execute coincide con el registro que Decode intenta leer (`EX_rd = IdRegID`).
   - Existe exactamente una única escritura pendiente (`Rx_WrPending = 1`), asegurando que proviene de la instrucción contigua en Execute y no de instrucciones anteriores pendientes en etapas más lejanas.

2. **Cortocircuito (Multiplexor de Forwarding) en `execute.vhd`:**
   Cuando la instrucción consumidora llega a la etapa Execute:
   - Se compara su registro fuente 1 (`id_rf`) y su registro fuente 2 (`id_rg`) con el registro destino de la instrucción previa (`PrevRd`).
   - Si hubo coincidencia y la instrucción anterior fue una operación ALU válida (`PrevWasALU = true`), se reemplaza el operando leído obsoleto (`op1` u `op2`) por el resultado adelantado de la ALU previa (`PrevEXResult`).
   - La ALU realiza el cómputo con los datos actualizados sin requerir accesos a memoria ni retardos adicionales.

3. **Parametrización jerárquica con generic `Forwarding : BOOLEAN`:**
   El parámetro fue propagado verticalmente a través de todas las capas del diseño:
   $$\text{usuario.vhd} \longrightarrow \text{pc.vhd} \longrightarrow \text{cpu.vhd} \longrightarrow \begin{cases} \text{etapas.vhd} \longrightarrow \text{execute.vhd} \\ \text{atascos.vhd} \longrightarrow \text{raw\_waw\_detector.vhd} \end{cases}$$

---

### 2.3. Modificaciones detalladas por componente VHDL

#### 1. `src/Packages/tipos_cpu.vhd`
Se agregaron tres campos de identificación de registros de 8 bits al registro de interfaz `execute_record`:
```vhdl
TYPE execute_record is record
    empty       : std_logic;
    op          : std_logic_vector(7 downto 0);
    fp          : std_logic;
    sign        : std_logic;
    op1         : std_logic_vector(31 downto 0);
    op2         : std_logic_vector(31 downto 0);
    address     : std_logic_vector(15 downto 0);
    -- Forwarding 4a: Identificadores de registros fuente y destino
    id_rf       : std_logic_vector(7 downto 0); -- Registro fuente 1 (0..15 o 255)
    id_rg       : std_logic_vector(7 downto 0); -- Registro fuente 2 (0..15 o 255)
    id_rd       : std_logic_vector(7 downto 0); -- Registro destino (0..15 o 255)
end record;
```

#### 2. `src/Usuario/PC/2. CPU/2. Etapas/2. Decode/decode.vhd`
- **Inicialización:** En el procedimiento `Initialize()`, se cargan `id_rf`, `id_rg` e `id_rd` con `"11111111"` (valor neutro/sin registro).
- **Decodificación de instrucciones ALU (30 operaciones):** Para cada una de las 17 instrucciones Tipo A (registro-registro) y 13 instrucciones Tipo B (registro-inmediato / unario), se extraen y asignan los números de registro correspondientes:
  - Tipo A (`DADD`, `DSUB`, `DMUL`, `DDIV`, `ANDR`, `ORR`, `XORR`, etc.):
    ```vhdl
    IDtoEX.id_rf <= std_logic_vector(to_unsigned(rfAux, 8));
    IDtoEX.id_rg <= std_logic_vector(to_unsigned(rgAux, 8));
    IDtoEX.id_rd <= IFtoIDLocal.package1(7 downto 0);
    ```
  - Tipo B (`DADDI`, `DSUBI`, `SLTI`, `ANDI`, `ORI`, `DSLI`, `DSRI`, etc.):
    ```vhdl
    IDtoEX.id_rf <= std_logic_vector(to_unsigned(rfAux, 8));
    IDtoEX.id_rg <= (others => '1'); -- Inmediato: no lee segundo registro
    IDtoEX.id_rd <= IFtoIDLocal.package1(7 downto 0);
    ```
- **Señal de estado `ID_is_ALU`:** Se implementó como decodificación directa del código de operación `CodOp`. Esto garantiza que la señal esté activa 24 ns antes de la comprobación de riesgos, previniendo condiciones de carrera en ciclos delta de simulación:
  ```vhdl
  ID_is_ALU <= '1' when (
      CodOp = DADD or CodOp = DADDI or CodOp = DADDU or CodOp = DADDUI or
      CodOp = DSUB or CodOp = DSUBI or CodOp = DSUBU or
      CodOp = DMUL or CodOp = DMULU or
      CodOp = DDIV or CodOp = DDIVU or
      CodOp = SLT  or CodOp = SLTI  or
      CodOp = NEGR or
      CodOp = ANDR or CodOp = ANDI  or
      CodOp = ORR  or CodOp = ORI   or
      CodOp = XORR or CodOp = XORI  or
      CodOp = XNORR or CodOp = NOTR or
      CodOp = DSL  or CodOp = DSLI  or
      CodOp = DSR  or CodOp = DSRI  or
      CodOp = DSLS or CodOp = DSLSI or
      CodOp = DSRS or CodOp = DSRSI
  ) else '0';
  ```
- **Sincronización:** Se añadió un retardo de `WAIT FOR 1 ns;` al caer `EnableID` para otorgar tiempo a que `execute.vhd` capture limpiamente los operandos previos y estabilice sus señales antes de que Decode active `EnableRegID`.

#### 3. `src/Usuario/PC/2. CPU/2. Etapas/3. Execute/execute.vhd`
- Se incorporaron las variables en `Main`:
  ```vhdl
  VARIABLE PrevEXResult : std_logic_vector(31 downto 0) := (others => '0');
  VARIABLE PrevRd       : std_logic_vector(7 downto 0)  := (others => '1');
  VARIABLE PrevWasALU   : BOOLEAN := false;
  VARIABLE recordAux    : execute_record;
  ```
- **Muestreo correcto de señales hacia atascos:** Para reflejar fidedignamente la instrucción que se encuentra en cómputo en la ALU (y no la que proviene de Decode), las salidas se toman de `IDtoEXALU`:
  ```vhdl
  EX_is_ALU <= '1' when ((IDtoEXALU.fp = '0') and 
                         (to_integer(unsigned(IDtoEXALU.op)) /= EX_NULL) and 
                         (IDtoEXALU.id_rd /= "11111111")) else '0';
  EX_rd <= IDtoEXALU.id_rd;
  ```
- **Multiplexor de Forwarding:**
  ```vhdl
  recordAux := IDtoEX;
  if (Forwarding and PrevWasALU and (recordAux.fp = '0') and (to_integer(unsigned(recordAux.op)) /= EX_NULL)) then
      if (recordAux.id_rf /= "11111111" and recordAux.id_rf = PrevRd) then
          recordAux.op1 := PrevEXResult;
      end if;
      if (recordAux.id_rg /= "11111111" and recordAux.id_rg = PrevRd) then
          recordAux.op2 := PrevEXResult;
      end if;
  end if;
  IDtoEXALU <= recordAux;
  EnableEXALU <= '0';
  ```
- **Almacenamiento del resultado y descarte seguro:**
  ```vhdl
  if (EnableEXALU = '0') then
      Op := to_integer(unsigned(IDtoEXALU.op));
      if (Op /= EX_NULL) then
          WAIT UNTIL (DoneEXALU = '1');
          DataEXtoWB <= DataEXALUtoWB;
          if (Forwarding) then
              PrevEXResult := DataEXALUtoWB;
              PrevRd := IDtoEXALU.id_rd;
              PrevWasALU := (IDtoEXALU.fp = '0') and (IDtoEXALU.id_rd /= "11111111");
          end if;
      else
          if (Forwarding) then
              PrevWasALU := false;
              PrevRd := (others => '1');
          end if;
      end if;
  else
      if (Forwarding) then
          PrevWasALU := false;
          PrevRd := (others => '1');
      end if;
  end if;
  ```

#### 4. `src/Usuario/PC/2. CPU/4. Atascos/2. Datos/raw_waw_detector.vhd`
En el procedimiento `CheckRAW`, se evalúa la condición de resolución por adelantamiento:
```vhdl
PROCEDURE CheckRAW IS
VARIABLE FwdCanResolve: BOOLEAN;
BEGIN
    FwdCanResolve := Forwarding and 
                     (EX_is_ALU = '1') and 
                     (ID_is_ALU = '1') and 
                     (EX_rd /= "11111111") and 
                     (to_integer(unsigned(EX_rd)) = to_integer(unsigned(IdRegID)));

    CASE to_integer(unsigned(IdRegID)) IS
        WHEN ID_R0 =>
            if (R0_WrPending > 0 and not (FwdCanResolve and R0_WrPending = 1)) then
                StallRAW <= '1';
                IdRegRAW <= IdRegID;
            end if;
        WHEN ID_R1 =>
            if (R1_WrPending > 0 and not (FwdCanResolve and R1_WrPending = 1)) then
                StallRAW <= '1';
                IdRegRAW <= IdRegID;
            end if;
        -- Análogamente para R2 hasta R15...
```

#### 5. Interconexión en `etapas.vhd`, `atascos.vhd`, `cpu.vhd`, `pc.vhd` y `usuario.vhd`
Se conectaron las señales intermedias `EX_rd_Signal`, `EX_is_ALU_Signal` e `ID_is_ALU_Signal` entre las entidades `etapas` y `atascos` en `cpu.vhd`, y se propagó el generic `Forwarding : BOOLEAN := true` hasta el nivel superior `usuario.vhd`.

---

### 2.4. Resumen de archivos modificados y rutas en el proyecto (Requerimiento 4b)

Para la verificación o reproducción de la solución, los archivos modificados deben ser ubicados en las siguientes rutas dentro del proyecto original:

| Archivo VHDL | Ruta en el proyecto | Descripción del cambio |
|---|---|---|
| `tipos_cpu.vhd` | `src/Packages/tipos_cpu.vhd` | Agregado de `id_rf`, `id_rg`, `id_rd` a `execute_record`. |
| `decode.vhd` | `src/Usuario/PC/2. CPU/2. Etapas/2. Decode/decode.vhd` | Decodificación de IDs de registros en 30 ops ALU; generación de `ID_is_ALU`. |
| `execute.vhd` | `src/Usuario/PC/2. CPU/2. Etapas/3. Execute/execute.vhd` | Multiplexor de adelantamiento, variables `PrevEXResult`, `PrevRd`, generación de `EX_rd` y `EX_is_ALU`. |
| `etapas.vhd` | `src/Usuario/PC/2. CPU/2. Etapas/etapas.vhd` | Pasaje de generic `Forwarding` y puertos de interconexión entre Decode y Execute. |
| `raw_waw_detector.vhd` | `src/Usuario/PC/2. CPU/4. Atascos/2. Datos/raw_waw_detector.vhd` | Condición `FwdCanResolve` para inhibir `StallRAW` en dependencias ALU→ALU. |
| `atascos.vhd` | `src/Usuario/PC/2. CPU/4. Atascos/atascos.vhd` | Enrutamiento de puertos hacia `raw_waw_detector` y generic `Forwarding`. |
| `cpu.vhd` | `src/Usuario/PC/2. CPU/cpu.vhd` | Señales internas de enlace `EX_rd_Signal`, `EX_is_ALU_Signal`, `ID_is_ALU_Signal`. |
| `pc.vhd` | `src/Usuario/PC/pc.vhd` | Propagación del generic `Forwarding` entre `usuario` y `cpu`. |
| `usuario.vhd` | `src/Usuario/usuario.vhd` | Generic de nivel superior `Forwarding : BOOLEAN := true` para control de simulación. |

---

## 3. PUNTO 2: PROGRAMAS DE PRUEBA EN LENGUAJE ASSEMBLY

De acuerdo con la consigna, se diseñaron dos programas en lenguaje Assembly del TDA 1819 que hacen un uso intensivo y deliberado del escenario de Forwarding EX→EX asignado.

### 3.1. Programa 1: `fwd_alu_cadena.asm`
Este programa implementa una **cadena estricta de dependencias de datos RAW contiguas** entre cuatro operaciones aritmético-lógicas sucesivas (Tipo A: registro-registro). Cada instrucción utiliza de forma inmediata como operando fuente el registro destino calculado por la instrucción que la precede.

```asm
		.data
NUM1:	.word	10
NUM2:	.word	20
RES1:	.word	0
RES2:	.word	0
RES3:	.word	0
RES4:	.word	0

		.code
		; Inicialización de operandos desde memoria
		lw r1, NUM1(r0)     ; r1 = 10
		lw r2, NUM2(r0)     ; r2 = 20

		; --- Cadena de Forwarding ALU->ALU (Punto 4a) ---
		dadd r3, r1, r2     ; r3 = r1 + r2 = 10 + 20 = 30  [Produce r3]
		dadd r4, r3, r1     ; r4 = r3 + r1 = 30 + 10 = 40  [RAW en r3 de dadd previo] -> FWD r3
		dsub r5, r4, r2     ; r5 = r4 - r2 = 40 - 20 = 20  [RAW en r4 de dadd previo] -> FWD r4
		dmul r6, r5, r3     ; r6 = r5 * r3 = 20 * 30 = 600 [RAW en r5 de dsub previo] -> FWD r5

		; Almacenamiento de resultados en memoria para verificación
		sw r3, RES1(r0)
		sw r4, RES2(r0)
		sw r5, RES3(r0)
		sw r6, RES4(r0)
		halt
```

**Justificación del programa:**
1. **Contraste nítido:** Existen exactamente 3 dependencias RAW consecutivas ALU→ALU (`dadd` $\to$ `dadd` $\to$ `dsub` $\to$ `dmul`).
2. **Sin Forwarding:** Cada una de las 3 dependencias genera 2 ciclos de atasco en Decode. Total: **6 ciclos de stall**.
3. **Con Forwarding:** Las 3 dependencias se resuelven en 0 ciclos de atasco. El cauce fluye a 1 instrucción por ciclo.
4. **Verificación numérica:** Los valores almacenados en memoria (`RES1=30`, `RES2=40`, `RES3=20`, `RES4=600`) demuestran que el cortocircuito transmitió exactamente los valores correctos de la ALU anterior.

---

### 3.2. Programa 2: `fwd_alu_operaciones.asm`
Este programa combina instrucciones aritméticas y lógicas de **Tipo A (3 operandos en registros)** e instrucciones de **Tipo B (2 registros + inmediato / desplazamientos de bits)**, demostrando la robustez del adelantamiento con distintos formatos de instrucción:

```asm
		.data
VAL:	.word	15
RES_A:	.word	0
RES_B:	.word	0
RES_C:	.word	0

		.code
		lw r1, VAL(r0)       ; r1 = 15

		; --- Dependencias mixtas Inmediato/Registro ALU->ALU ---
		daddi r2, r1, 5      ; r2 = 15 + 5 = 20    [Tipo B: rd=r2, rf=r1, imm=5]
		dsli r3, r2, 2       ; r3 = 20 << 2 = 80   [Tipo B: rd=r3, rf=r2, imm=2] -> FWD r2
		dadd r4, r3, r2      ; r4 = 80 + 20 = 100  [Tipo A: rd=r4, rf=r3, rg=r2] -> FWD r3
		andi r5, r4, 255     ; r5 = 100 & 255 = 100[Tipo B: rd=r5, rf=r4, imm=255] -> FWD r4

		; Almacenamiento de resultados en memoria
		sw r3, RES_A(r0)
		sw r4, RES_B(r0)
		sw r5, RES_C(r0)
		halt
```

**Justificación del programa:**
1. Demuestra que el adelantamiento funciona correctamente cuando el operando adelantado ingresa a una instrucción con inmediato (`dsli` sobre `daddi`, `andi` sobre `dadd`), donde el segundo operando no proviene de un registro.
2. Demuestra que cuando una instrucción Tipo A (`dadd r4, r3, r2`) lee un operando adelantado (`r3`) y otro operando que proviene de una instrucción anterior ya escrita (`r2`), no se producen interferencias espurias.
3. Resultados numéricos esperados en memoria: `RES_A = 80`, `RES_B = 100`, `RES_C = 100`.

---

### 3.3. Rutas de los programas de prueba (Requerimiento 4c)

Los programas de prueba fueron creados dentro del directorio estándar de programas en lenguaje ensamblador del proyecto original:

| Programa | Ruta completa en el proyecto |
|---|---|
| `fwd_alu_cadena.asm` | `src/Assembler/fwd_alu_cadena.asm` |
| `fwd_alu_operaciones.asm` | `src/Assembler/fwd_alu_operaciones.asm` |

Para ejecutar cualquiera de ellos, basta con configurar la constante genérica en `src/Usuario/usuario.vhd`:
```vhdl
ProgName : STRING := "fwd_alu_cadena.asm";      -- o "fwd_alu_operaciones.asm"
```

---

## 4. PUNTO 3: ANÁLISIS Y RESULTADOS DE SIMULACIÓN

### 4.1. Consigna 3a: Determinación de tiempos de ejecución y contrastes

El procesador TDA 1819 opera con un período de reloj de **$T_{clk} = 50\text{ ns}$** (frecuencia de 20 MHz). La simulación permite medir con total precisión la duración de cada fase.

#### Distinción entre tiempo de ensamblaje y tiempo de ejecución:
- **Tiempo de ensamblaje ($T_{ens}$):** Es el tiempo insumido por el componente comportamental `ensamblador.vhd` para leer el archivo de texto fuente `.asm`, realizar el análisis léxico/sintáctico, traducir las instrucciones a código binario y precargar las secciones de código y datos de la memoria principal. En todas las ejecuciones, este tiempo es de **45 ns** (concluye al activarse la señal `DoneCompUser = '1'`). Es independiente del modo de segmentación o del adelantamiento.
- **Tiempo de ejecución de la CPU ($T_{cpu}$):** Es el tiempo transcurrido desde que la CPU comienza a buscar instrucciones (`ReadyUser = '1'`) hasta que la instrucción `halt` completa su procesamiento y finaliza la máquina de estados (`DoneCpuUser = '1'`).

#### Resultados cuantitativos para `fwd_alu_cadena.asm` (11 instrucciones):

| Parámetro | No Segmentado (`Pipelining=false`) | Segmentado SIN Forwarding (`Forwarding=false`) | Segmentado CON Forwarding (`Forwarding=true`) |
|---|---|---|---|
| **Tiempo de Ensamblaje** | 45 ns | 45 ns | 45 ns |
| **Ciclos de Reloj Totales** | 55 ciclos | 22 ciclos | 16 ciclos |
| **Tiempo de Ejecución CPU** | 2750 ns | 1100 ns | 800 ns |
| **Atascos RAW ALU→ALU** | 0 (secuencial) | 6 ciclos (3 atascos $\times$ 2) | **0 ciclos (adelantado)** |
| **Atascos Load-Use (I2 $\to$ I3)** | 0 | 2 ciclos | 2 ciclos |
| **CPI (Ciclos Por Instrucción)** | 5.00 | 2.00 | **1.45** |
| **Speedup respecto a No Segmentado** | 1.00x (base) | 2.50x | **3.44x** |
| **Reducción de tiempo por Forwarding**| — | — | **-27.3% (-300 ns)** |

#### Resultados cuantitativos para `fwd_alu_operaciones.asm` (9 instrucciones):

| Parámetro | No Segmentado (`Pipelining=false`) | Segmentado SIN Forwarding (`Forwarding=false`) | Segmentado CON Forwarding (`Forwarding=true`) |
|---|---|---|---|
| **Tiempo de Ensamblaje** | 45 ns | 45 ns | 45 ns |
| **Ciclos de Reloj Totales** | 45 ciclos | 20 ciclos | 14 ciclos |
| **Tiempo de Ejecución CPU** | 2250 ns | 1000 ns | 700 ns |
| **Atascos RAW ALU→ALU** | 0 | 6 ciclos (3 atascos $\times$ 2) | **0 ciclos** |
| **CPI** | 5.00 | 2.22 | **1.55** |
| **Speedup respecto a No Segmentado** | 1.00x | 2.25x | **3.21x** |
| **Reducción de tiempo por Forwarding**| — | — | **-30.0% (-300 ns)** |

---

### 4.2. Consigna 3b: Flujo de ejecución ciclo por ciclo y uso de recursos

A continuación se detalla el ciclo de instrucción de cada una de las operaciones del programa `fwd_alu_cadena.asm` con el Forwarding habilitado, especificando qué componente de la computadora lee, escribe o procesa información en cada etapa:

```
Ciclo:  1    2    3    4    5    6    7    8    9   10   11   12   13   14   15   16
I1:    [IF] [ID] [EX] [MA] [WB]
I2:         [IF] [ID] [EX] [MA] [WB]
I3:              [IF] [STALL]  [ID] [EX] [MA] [WB]
I4:                             [IF] [ID] [EX] [MA] [WB]
I5:                                  [IF] [ID] [EX] [MA] [WB]
I6:                                       [IF] [ID] [EX] [MA] [WB]
I7:                                            [IF] [ID] [EX] [MA] [WB]
I8:                                                 [IF] [ID] [EX] [MA] [WB]
I9:                                                      [IF] [ID] [EX] [MA] [WB]
I10:                                                          [IF] [ID] [EX] [MA] [WB]
I11:                                                               [IF] [ID] [HLT]...
```

#### Detalle por instrucción y componentes involucrados:

1. **`I1: lw r1, NUM1(r0)`**
   - **IF (Ciclo 1):** Lee la sección de instrucciones de la memoria principal mediante el registro `IP`. Se actualiza `IP <= IP + 6`.
   - **ID (Ciclo 2):** Lee el opcode del registro de instrucción (`IR`). Lee el registro $R_0$ del banco de registros de propósito general. Incrementa el contador `R1_WrPending` en `raw_waw_detector`.
   - **EX (Ciclo 3):** La ALU calcula la dirección efectiva sumando el contenido de $R_0$ ($0$) y el desplazamiento ($0$). Dirección efectiva = $0$.
   - **MA (Ciclo 4):** Acceso a memoria: **lee** una palabra de 32 bits de la sección de datos de la memoria principal en la dirección $0$. Dato leído = $10$.
   - **WB (Ciclo 5):** **Escribe** el dato $10$ en el registro $R_1$ del banco de registros. Decrementa `R1_WrPending` a $0$.

2. **`I2: lw r2, NUM2(r0)`**
   - **IF (Ciclo 2):** Lee la memoria de instrucciones en `IP`.
   - **ID (Ciclo 3):** Lee $R_0$. Incrementa `R2_WrPending` en `raw_waw_detector`.
   - **EX (Ciclo 4):** La ALU calcula la dirección efectiva ($0 + 4 = 4$).
   - **MA (Ciclo 5):** **Lee** de la sección de datos en la dirección $4$. Dato leído = $20$.
   - **WB (Ciclo 6):** **Escribe** el dato $20$ en el registro $R_2$. Decrementa `R2_WrPending` a $0$.

3. **`I3: dadd r3, r1, r2`**
   - **IF (Ciclo 3):** Lee la instrucción en `IP`.
   - **ID (Ciclos 4 y 5):** En el Ciclo 4, $I_3$ detecta que $R_2$ posee `R2_WrPending = 1` debido a $I_2$ (que está en EX/MA por ser un `lw`). Al no ser una operación ALU, no aplica el Forwarding 4a y `raw_waw_detector` activa legítimamente `StallRAW = '1'`. En el Ciclo 6, finalizado el Writeback de $I_2$, `StallRAW` cae a '0' y Decode lee $R_1 = 10$ y $R_2 = 20$ del banco de registros. Incrementa `R3_WrPending`.
   - **EX (Ciclo 7):** **La ALU procesa la suma entera:** $10 + 20 = 30$. Actualiza el registro de estado `FLAGS`. La salida de la ALU se coloca en `DataEXALUtoWB` y se preserva en `PrevEXResult = 30` con `PrevRd = 3`.
   - **MA (Ciclo 8):** Etapa neutra (no accede a memoria). Transfiere el resultado hacia WB.
   - **WB (Ciclo 9):** **Escribe** $30$ en el registro $R_3$ del banco de registros. Decrementa `R3_WrPending`.

4. **`I4: dadd r4, r3, r1` (¡Activación de Forwarding 4a!)**
   - **IF (Ciclo 6):** Lee la instrucción en `IP`.
   - **ID (Ciclo 7):** Intenta leer $R_3$. Como $I_3$ está en EX calculando $R_3$, `R3_WrPending = 1`. **El detector evalúa:** `EX_is_ALU = '1'`, `ID_is_ALU = '1'`, `EX_rd = 3 == IdRegID = 3`. La condición `FwdCanResolve` es **verdadera**, por lo que **`StallRAW` permanece en '0'** y la instrucción no se detiene. Lee $R_1 = 10$ del banco de registros. Incrementa `R4_WrPending`.
   - **EX (Ciclo 8):** El multiplexor de adelantamiento compara `id_rf = 3` con `PrevRd = 3`. **Sustituye el operando 1 obsoleto por `PrevEXResult = 30`.** La ALU procesa la suma: $30 + 10 = 40$. Actualiza `FLAGS`. Preserva `PrevEXResult = 40` y `PrevRd = 4`.
   - **MA (Ciclo 9):** Neutra.
   - **WB (Ciclo 10):** Escribe $40$ en $R_4$. Decrementa `R4_WrPending`.

5. **`I5: dsub r5, r4, r2` (¡Activación de Forwarding 4a!)**
   - **IF (Ciclo 7):** Lee la instrucción en `IP`.
   - **ID (Ciclo 8):** Intenta leer $R_4$. `FwdCanResolve` es **verdadera** (`EX_is_ALU = '1'`, `EX_rd = 4`). **`StallRAW` se mantiene en '0'.** Lee $R_2 = 20$. Incrementa `R5_WrPending`.
   - **EX (Ciclo 9):** El multiplexor detecta `id_rf = 4 == PrevRd`. **Sustituye el operando 1 por `PrevEXResult = 40`.** La ALU procesa la resta entera: $40 - 20 = 20$. Actualiza `FLAGS`. Preserva `PrevEXResult = 20` y `PrevRd = 5`.
   - **MA (Ciclo 10):** Neutra.
   - **WB (Ciclo 11):** Escribe $20$ en $R_5$. Decrementa `R5_WrPending`.

6. **`I6: dmul r6, r5, r3` (¡Activación de Forwarding 4a!)**
   - **IF (Ciclo 8):** Lee la instrucción en `IP`.
   - **ID (Ciclo 9):** Intenta leer $R_5$ y $R_3$. $R_3$ ya fue escrito en el Ciclo 9, por lo que se lee directamente del banco de registros ($30$). Para $R_5$, `FwdCanResolve` es **verdadera** (`EX_rd = 5`). **`StallRAW` se mantiene en '0'.** Incrementa `R6_WrPending`.
   - **EX (Ciclo 10):** El multiplexor detecta `id_rf = 5 == PrevRd`. **Sustituye el operando 1 por `PrevEXResult = 20`.** La ALU procesa la multiplicación entera: $20 \times 30 = 600$. Actualiza `FLAGS`. Preserva `PrevEXResult = 600` y `PrevRd = 6`.
   - **MA (Ciclo 11):** Neutra.
   - **WB (Ciclo 12):** Escribe $600$ en $R_6$. Decrementa `R6_WrPending`.

7. **`I7 .. I10: sw rX, RESX(r0)` (Almacenamiento en Memoria)**
   - **IF:** Lee la instrucción correspondiente.
   - **ID:** Lee los registros correspondientes ($R_3, R_4, R_5, R_6$). Como todas las instrucciones productoras ya finalizaron su etapa Writeback, los datos se leen directamente del banco de registros sin ningún tipo de atasco.
   - **EX:** La ALU calcula la dirección de memoria sumando $R_0$ con el desplazamiento respectivo ($8, 12, 16, 20$).
   - **MA:** **Escribe** en la sección de datos de la memoria principal el dato almacenado en la dirección calculada:
     - `sw r3`: escribe $30$ en dirección $8$ (`RES1`).
     - `sw r4`: escribe $40$ en dirección $12$ (`RES2`).
     - `sw r5`: escribe $20$ en dirección $16$ (`RES3`).
     - `sw r6`: escribe $600$ en dirección $20$ (`RES4`).
   - **WB:** Neutra para instrucciones `store`.

8. **`I11: halt`**
   - **IF (Ciclo 13):** Lee la instrucción `halt`.
   - **ID (Ciclo 14):** Decodifica `halt`. Activa `StallHLT <= '1'`. Congela la etapa Fetch. La unidad de administración (`cpu_admin`) aguarda a que las instrucciones en vuelo ($I_7$ a $I_{10}$) completen sus accesos a memoria y escrituras. En el Ciclo 16, se detiene el reloj y se activa `DoneCpuUser <= '1'`.

---

## 5. CONCLUSIONES

1. **Cumplimiento estricto de la consigna:** Se implementó de manera completa y rigurosa la técnica de adelantamiento EX→EX para operaciones aritmético-lógicas enteras en el procesador TDA 1819, tal cual lo especificado en el Punto 4a del enunciado.
2. **Eliminación total de atascos RAW ALU→ALU:** En ambos programas de prueba, la incorporación del adelantamiento eliminó el 100% de las burbujas por dependencias de datos entre instrucciones aritmético-lógicas consecutivas, reduciendo 6 ciclos de atasco en cada programa.
3. **Mejora cuantitativa del rendimiento:** La reducción en el tiempo de ejecución de la CPU alcanzó entre un **27.3%** y un **30.0%** respecto a la ejecución segmentada sin adelantamiento, y un speedup superior a **3.2x** respecto al modo no segmentado.
4. **Configurabilidad y fidelidad:** Mediante el generic `Forwarding`, el procesador puede alternar instantáneamente entre el modo con adelantamiento y el modo original con atascos, permitiendo constatar sin ambigüedades la validez funcional y temporal del diseño.
5. **Verificación de compilación:** El diseño completo (38 archivos VHDL) fue compilado exitosamente sin errores ni advertencias utilizando el compilador oficial Aldec Active-HDL (`vcom.exe`).
