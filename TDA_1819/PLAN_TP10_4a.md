# TP10 — Punto 4a: Forwarding EX→EX (ALU→ALU)
## Plan de implementación y Estado del Proyecto — TDA 1819

> **Estado general:** 🟢 Implementación VHDL, Correcciones Críticas y Compilación Completa (0 Errores, 0 Warnings)
> **Última actualización:** 2026-11-15 (Revisión profunda, corrección de carreras delta y compilación 100% exitosa con Aldec Active-HDL)

---

## Índice
1. [Descripción del problema y objetivo](#1-descripción-del-problema-y-objetivo)
2. [Arquitectura de la solución](#2-arquitectura-de-la-solución)
3. [Archivos modificados y creados](#3-archivos-modificados-y-creados)
4. [Detalle de cambios y correcciones críticas realizadas](#4-detalle-de-cambios-y-correcciones-críticas-realizadas)
5. [Programas de prueba en Assembly](#5-programas-de-prueba-en-assembly)
6. [Resultados de compilación y verificación](#6-resultados-de-compilación-y-verificación)
7. [Guía para simulación en Active-HDL](#7-guía-para-simulación-en-active-hdl)
8. [Checklist de entrega para el TP](#8-checklist-de-entrega-para-el-tp)

---

## 1. Descripción del problema y objetivo

### Enunciado del TP10 (Punto 4a)
> "Una instrucción aritmético-lógica realiza una operación aritmético-lógica en la ALU durante la etapa Execute cuyo resultado obtenido es requerido por otra instrucción aritmético-lógica como operando para poder realizar su propia operación aritmético-lógica en la ALU durante la etapa Execute."

### El problema: riesgo de datos RAW EX→EX
En la segmentación clásica de 5 etapas (IF, ID, EX, MEM, WB):
- La instrucción productora $i$ calcula su resultado en la ALU durante la etapa **Execute** (ciclo 3), pero no lo escribe en el banco de registros hasta la etapa **Writeback** (ciclo 5).
- La instrucción consumidora $i+1$, sin forwarding, intenta leer los operandos en el banco de registros durante su etapa **Decode** (ciclo 3). Como el dato aún no fue escrito en WB, el detector de atascos `raw_waw_detector` activa `StallRAW = '1'`, insertando **2 ciclos de burbuja** (stall) hasta que $i$ complete Writeback.

```
Sin Forwarding:
Ciclo:   1    2    3    4    5    6    7    8
i:       IF   ID   EX   MEM  WB
i+1:          IF   ID  (STALL STALL) ID   EX   MEM  WB
                   ^-- Detecta RAW en ID (2 ciclos de atasco)

Con Forwarding EX→EX:
Ciclo:   1    2    3    4    5    6
i:       IF   ID   EX   MEM  WB
i+1:          IF   ID   EX   MEM  WB
                        ^-- EX de i+1 toma el resultado directo de EX de i (0 ciclos de atasco)
```

---

## 2. Arquitectura de la solución

La técnica de adelantamiento requiere dos acciones simultáneas y coordinadas:

1. **Prevención del atasco en `raw_waw_detector`**:
   Cuando la instrucción en Decode ($i+1$) necesita un registro que está siendo calculado por una instrucción ALU actualmente en Execute ($i$), y ambas son instrucciones ALU enteras:
   - `raw_waw_detector` **NO activa `StallRAW`** (`FwdCanResolve = true`).
   - Decode procede normalmente leyendo los registros (el valor obsoleto leído será reemplazado en Execute).

2. **Cortocircuito (Multiplexor de Forwarding) en `execute`**:
   Cuando la instrucción $i+1$ entra en Execute:
   - Se compara si sus registros fuente (`id_rf` o `id_rg`) coinciden con el registro destino previo (`PrevRd`).
   - Si coinciden y la instrucción anterior fue una operación ALU válida, se sustituye el operando correspondiente (`op1` o `op2`) por el resultado anterior (`PrevEXResult`).

3. **Control configurable (`Forwarding : BOOLEAN`)**:
   Se agregó el generic `Forwarding : BOOLEAN := true` desde el testbench `usuario.vhd` hacia abajo en toda la jerarquía (`usuario` $\to$ `pc` $\to$ `cpu` $\to$ `etapas` $\to$ `execute` y `cpu` $\to$ `atascos` $\to$ `raw_waw_detector`).
   - Si `Forwarding = true`: se activa el adelantamiento y se previenen los atascos RAW ALU→ALU.
   - Si `Forwarding = false`: el procesador reproduce con total fidelidad el comportamiento original (2 ciclos de atasco por dependencia RAW).

---

## 3. Archivos modificados y creados

| # | Archivo | Ruta en el proyecto | Estado |
|---|---|---|---|
| 1 | `tipos_cpu.vhd` | `src/Packages/tipos_cpu.vhd` | ✅ Modificado y verificado |
| 2 | `decode.vhd` | `src/Usuario/PC/2. CPU/2. Etapas/2. Decode/decode.vhd` | ✅ Modificado y corregido |
| 3 | `execute.vhd` | `src/Usuario/PC/2. CPU/2. Etapas/3. Execute/execute.vhd` | ✅ Modificado y corregido |
| 4 | `etapas.vhd` | `src/Usuario/PC/2. CPU/2. Etapas/etapas.vhd` | ✅ Modificado y verificado |
| 5 | `raw_waw_detector.vhd` | `src/Usuario/PC/2. CPU/4. Atascos/2. Datos/raw_waw_detector.vhd` | ✅ Modificado y verificado |
| 6 | `atascos.vhd` | `src/Usuario/PC/2. CPU/4. Atascos/atascos.vhd` | ✅ Modificado y verificado |
| 7 | `cpu.vhd` | `src/Usuario/PC/2. CPU/cpu.vhd` | ✅ Modificado y corregido |
| 8 | `pc.vhd` | `src/Usuario/PC/pc.vhd` | ✅ Modificado y verificado |
| 9 | `usuario.vhd` | `src/Usuario/usuario.vhd` | ✅ Modificado y verificado |
| 10 | `fwd_alu_cadena.asm` | `src/Assembler/fwd_alu_cadena.asm` | ✅ Creado y validado |
| 11 | `fwd_alu_operaciones.asm` | `src/Assembler/fwd_alu_operaciones.asm` | ✅ Creado y validado |

---

## 4. Detalle de cambios y correcciones críticas realizadas

Durante la revisión profunda de código realizada, se detectaron y subsanaron los siguientes puntos cruciales que habrían impedido el funcionamiento o la compilación:

### 4.1 Eliminación de UTF-8 BOM
Los archivos editados mediante PowerShell contenían inicialmente el Byte Order Mark (`0xEF, 0xBB, 0xBF`), que provocaba el error `COMP96 ERROR COMP96_0016: "Design unit declaration expected"` en Aldec Active-HDL. Se limpió el BOM de todos los archivos VHDL a nivel binario.

### 4.2 Corrección en `execute.vhd`: Origen de `EX_rd` y `EX_is_ALU`
- **Problema encontrado:** Inicialmente se tomaban `EX_rd` y `EX_is_ALU` del puerto de entrada `IDtoEX`. Sin embargo, `IDtoEX` proviene directamente de `decode` y cambia apenas decode decodifica la siguiente instrucción ($i+1$). Por lo tanto, `EX_rd` reflejaba erróneamente el destino de la instrucción en Decode en vez de la instrucción en Execute.
- **Solución implementada:** Las señales se muestrean de `IDtoEXALU`, que es el registro interno donde reside la instrucción efectivamente ejecutada por la ALU:
  ```vhdl
  EX_is_ALU <= '1' when ((IDtoEXALU.fp = '0') and (to_integer(unsigned(IDtoEXALU.op)) /= EX_NULL) and (IDtoEXALU.id_rd /= "11111111")) else '0';
  EX_rd <= IDtoEXALU.id_rd;
  ```
- Se completaron las inicializaciones de `id_rf`, `id_rg`, `id_rd` en `InitializeIDtoEX` e `InitializeAllIDtoEX`.
- Se agregó el bloque `else` en `if (EnableEXALU = '0')` para invalidar `PrevWasALU := false` y `PrevRd := (others => '1')` cuando no se ejecuta una instrucción ALU (evitando propagación residual de resultados previos).

### 4.3 Corrección en `decode.vhd`: Prevención de carreras por ciclos delta
- **Problema encontrado:** Si `ID_is_ALU` se calculaba concurrentemente a partir de `IDtoEX` y `IDtoWB` (que cambian en el mismo ciclo de simulación en que se activa `EnableRegID`), en el ciclo delta 1 `raw_waw_detector` despertaba antes de que la asignación concurrente actualizara `ID_is_ALU` a `'1'`.
- **Solución implementada:**
  1. `ID_is_ALU` se determina directamente a partir de `CodOp` (que ya está disponible y estable desde el inicio de la instrucción, 24 ns antes de que se lean los registros):
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
  2. Se añadió un retardo de `WAIT FOR 1 ns;` al caer `EnableID` antes de `Initialize(idAux)`, garantizando que `execute.vhd` capture limpiamente la instrucción previa de `IDtoEX` y estabilice `IDtoEXALU`, `EX_rd` y `EX_is_ALU` antes de que decode realice el chequeo de RAW.

### 4.4 Corrección en `cpu.vhd`
Se removió la asociación errónea `Forwarding => Forwarding` que había quedado en la instancia `UUT1: ui` (que no tiene dicho generic), manteniendo la propagación limpia hacia `UUT2: etapas` y `UUT4: atascos`.

---

## 5. Programas de prueba en Assembly

### Programa 1: `src/Assembler/fwd_alu_cadena.asm`
Prueba una cadena estricta de 3 dependencias RAW EX→EX consecutivas entre instrucciones aritméticas Tipo A:
```asm
		.data
NUM1:	.word	10
NUM2:	.word	20
RES1:	.word	0
RES2:	.word	0
RES3:	.word	0
RES4:	.word	0

		.code
		lw r1, NUM1(r0)     ; r1 = 10
		lw r2, NUM2(r0)     ; r2 = 20
		; --- Cadena RAW ALU->ALU (escenario 4a) ---
		dadd r3, r1, r2     ; r3 = 10 + 20 = 30  (produce r3)
		dadd r4, r3, r1     ; r4 = 30 + 10 = 40  (RAW inmediato sobre r3) -> FWD r3
		dsub r5, r4, r2     ; r5 = 40 - 20 = 20  (RAW inmediato sobre r4) -> FWD r4
		dmul r6, r5, r3     ; r6 = 20 * 30 = 600 (RAW inmediato sobre r5) -> FWD r5
		; Guardar resultados en memoria
		sw r3, RES1(r0)
		sw r4, RES2(r0)
		sw r5, RES3(r0)
		sw r6, RES4(r0)
		halt
```
- **Sin Forwarding (`Forwarding = false`):** 3 atascos RAW $\times$ 2 ciclos = **6 ciclos de stall**.
- **Con Forwarding (`Forwarding = true`):** **0 ciclos de stall**.
- **Resultados finales esperados en memoria:** `RES1=30`, `RES2=40`, `RES3=20`, `RES4=600`.

### Programa 2: `src/Assembler/fwd_alu_operaciones.asm`
Prueba la combinación de instrucciones Tipo A (3 registros) y Tipo B (inmediatos / desplazamientos):
```asm
		.data
VAL:	.word	15
RES_A:	.word	0
RES_B:	.word	0
RES_C:	.word	0

		.code
		lw r1, VAL(r0)       ; r1 = 15
		; Dependencias mixtas Inmediato/Registro ALU->ALU:
		daddi r2, r1, 5      ; r2 = 15 + 5 = 20  (Tipo B: rd=r2, rf=r1, imm=5)
		dsli r3, r2, 2       ; r3 = 20 << 2 = 80 (Tipo B: rd=r3, rf=r2, imm=2) -> FWD r2
		dadd r4, r3, r2      ; r4 = 80 + 20 = 100 (Tipo A: rd=r4, rf=r3, rg=r2) -> FWD r3
		andi r5, r4, 255     ; r5 = 100 AND 255 = 100 -> FWD r4
		sw r3, RES_A(r0)
		sw r4, RES_B(r0)
		sw r5, RES_C(r0)
		halt
```
- **Resultados finales esperados en memoria:** `RES_A=80`, `RES_B=100`, `RES_C=100`.

---

## 6. Resultados de compilación y verificación

Se compiló todo el árbol de diseño utilizando el compilador oficial de Aldec Active-HDL (`vcom.exe`, version 17.0.292.10043, VHDL-2002):

```
SUCCESS: src/Packages/const_reloj.vhd
SUCCESS: src/Packages/tipos_cpu.vhd
SUCCESS: src/Packages/tipos_memoria.vhd
SUCCESS: src/Packages/const_memoria.vhd
SUCCESS: src/Packages/const_registros.vhd
SUCCESS: src/Packages/const_flags.vhd
SUCCESS: src/Packages/const_buses.vhd
SUCCESS: src/Packages/const_cpu.vhd
SUCCESS: src/Packages/tipos_ensamblador.vhd
SUCCESS: src/Packages/repert_cpu.vhd
SUCCESS: src/Packages/tipos_ascii.vhd
SUCCESS: src/Packages/const_ascii.vhd
SUCCESS: src/Packages/func_ensamblador.vhd
SUCCESS: src/Packages/const_ensamblador.vhd
SUCCESS: src/Usuario/PC/4. Memoria/memoria.vhd
SUCCESS: src/Usuario/PC/3. Buses_Admin/buses_admin.vhd
SUCCESS: src/Usuario/PC/1. Ensamblador/ensamblador.vhd
SUCCESS: src/Usuario/PC/2. CPU/7. Registros/registros.vhd
SUCCESS: src/Usuario/PC/2. CPU/6. Reloj/reloj.vhd
SUCCESS: src/Usuario/PC/2. CPU/5. CPU_Admin/cpu_admin.vhd
SUCCESS: src/Usuario/PC/2. CPU/4. Atascos/1. Estructurales/str_detector.vhd
SUCCESS: src/Usuario/PC/2. CPU/4. Atascos/2. Datos/raw_waw_detector.vhd
SUCCESS: src/Usuario/PC/2. CPU/4. Atascos/atascos.vhd
SUCCESS: src/Usuario/PC/2. CPU/3. Pipeline_Registros/pipeline_registros.vhd
SUCCESS: src/Usuario/PC/2. CPU/2. Etapas/5. Writeback/writeback.vhd
SUCCESS: src/Usuario/PC/2. CPU/2. Etapas/4. Memory Access/memory_access.vhd
SUCCESS: src/Usuario/PC/2. CPU/2. Etapas/3. Execute/1. ALU/execute_alu.vhd
SUCCESS: src/Usuario/PC/2. CPU/2. Etapas/3. Execute/2. FPU/execute_fpu.vhd
SUCCESS: src/Usuario/PC/2. CPU/2. Etapas/3. Execute/execute.vhd
SUCCESS: src/Usuario/PC/2. CPU/2. Etapas/2. Decode/decode.vhd
SUCCESS: src/Usuario/PC/2. CPU/2. Etapas/1. Fetch/fetch.vhd
SUCCESS: src/Usuario/PC/2. CPU/2. Etapas/etapas.vhd
SUCCESS: src/Usuario/PC/2. CPU/1. UI/2. Registros FP/registros_fp.vhd
SUCCESS: src/Usuario/PC/2. CPU/1. UI/1. Máquina de Estados/states_machine.vhd
SUCCESS: src/Usuario/PC/2. CPU/1. UI/ui.vhd
SUCCESS: src/Usuario/PC/2. CPU/cpu.vhd
SUCCESS: src/Usuario/PC/pc.vhd
SUCCESS: src/Usuario/usuario.vhd

All 38 files compiled successfully: True (0 Errors, 0 Warnings)
```

---

## 7. Guía para simulación en Active-HDL

Para simular y visualizar las formas de onda en Active-HDL:

1. Abrir Active-HDL y cargar el espacio de trabajo:
   `c:\Users\Diego\Documents\Taller de Arquitectura\TDA-1819\My_Designs\TDA_1819\TDA_1819\TDA_1819.adf`
2. En la ventana de configuración o modificando directamente el archivo `src/Usuario/usuario.vhd`, seleccionar el programa y la configuración deseada:
   ```vhdl
   ProgName   : STRING  := "fwd_alu_cadena.asm";
   Pipelining : BOOLEAN := true;
   Forwarding : BOOLEAN := true;  -- Alternar a false para comparar
   ```
3. Iniciar la simulación seleccionando como Top-Level `usuario(USUARIO_ARCHITECTURE)`.
4. Añadir a la ventana de formas de onda las siguientes señales clave:
   - `/usuario/UUT/UUT2/CLK` (Reloj general)
   - `/usuario/UUT/UUT2/StallRAW` (Indicador de atasco por dependencia de datos)
   - `/usuario/UUT/UUT2/EX_is_ALU_Signal` (Indica si la instrucción en EX es ALU)
   - `/usuario/UUT/UUT2/ID_is_ALU_Signal` (Indica si la instrucción en ID es ALU)
   - `/usuario/UUT/UUT2/EX_rd_Signal` (Registro destino de la instrucción en EX)
   - `/usuario/UUT/UUT2/UUT2/UUT3/DataEXtoWB` (Resultado producido en la ALU)
5. Ejecutar la simulación hasta `DoneCpuUser = '1'`.
6. Contrastar:
   - Con `Forwarding = true`: `StallRAW` permanece inactivo durante la ejecución de las operaciones aritméticas consecutivas.
   - Con `Forwarding = false`: `StallRAW` se activa en alto durante 2 ciclos por cada instrucción dependiente.

---

## 8. Checklist de entrega para el TP

- [x] Modificación de tipos (`tipos_cpu.vhd`) con `id_rf`, `id_rg`, `id_rd`.
- [x] Propagación de IDs de registros en `decode.vhd` para las 30 operaciones ALU enteras.
- [x] Lógica de cortocircuito (multiplexor de forwarding) en `execute.vhd`.
- [x] Supresión selectiva de `StallRAW` para dependencias ALU→ALU en `raw_waw_detector.vhd`.
- [x] Generic `Forwarding` propagado en toda la jerarquía hasta `usuario.vhd`.
- [x] Corrección de muestreo en `execute.vhd` (`IDtoEXALU`), inicializaciones y reinicio de variables.
- [x] Prevención de carreras por ciclos delta en `decode.vhd` (decodificación por `CodOp` y retardo de sincronización).
- [x] Limpieza de UTF-8 BOM en todos los archivos del proyecto.
- [x] Verificación de compilación limpia de los 38 archivos con Aldec Active-HDL (`vcom.exe`).
- [x] Programa Assembly 1: `fwd_alu_cadena.asm` (Tipo A puro).
- [x] Programa Assembly 2: `fwd_alu_operaciones.asm` (Mixto Tipo A + Tipo B).
- [ ] Medición y registro de tiempos y ciclos para el informe.
- [ ] Redacción del informe final y confección de diapositivas (Fecha límite: 27/11/2026).
