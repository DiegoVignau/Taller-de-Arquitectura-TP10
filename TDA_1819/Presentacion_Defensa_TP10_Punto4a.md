# PRESENTACIÓN PARA DEFENSA ORAL
## Trabajo Práctico N° 10 — Procesador TDA 1819
### Ejercicio 4a: Implementación de la Técnica de Adelantamiento (Forwarding) EX→EX para Instrucciones Aritmético-Lógicas

**Cátedra:** Taller de Arquitectura — 2026  
**Fecha límite:** 27 de noviembre de 2026  

---

<!-- slide -->
## DIAPOSITIVA 1: CARÁTULA Y PRESENTACIÓN

### Título
**Implementación de Adelantamiento (Forwarding) EX→EX en el Procesador Segmentado TDA 1819**

### Subtítulo
Resolución del Punto 4a: Eliminación de atascos RAW entre instrucciones aritmético-lógicas consecutivas

### Integrantes del Grupo
* [Nombres y Apellidos de los alumnos]
* [Números de legajo]

### Contexto Académico
* **Materia:** Taller de Arquitectura
* **Año:** 2026
* **Tema:** TP10 — Extensión de funcionalidades en VHDL del procesador TDA 1819

> **Notas para el orador:**
> * Saludar al tribunal evaluador.
> * Presentar brevemente el tema asignado: Ejercicio 4a, correspondiente a la técnica de Forwarding EX→EX para operaciones de la ALU en el procesador didáctico TDA 1819.
> * Mencionar que el trabajo abarca el diseño VHDL, la creación de programas de prueba en Assembly, el análisis comparativo cuantitativo y la verificación exhaustiva mediante simulación.

---

<!-- slide -->
## DIAPOSITIVA 2: INTRODUCCIÓN Y CONTEXTO DEL PROCESADOR

### La Arquitectura TDA 1819
* Procesador segmentado de **5 etapas clásicas**:
  1. **IF (Fetch):** Búsqueda de instrucción en memoria.
  2. **ID (Decode):** Decodificación y lectura de registros de propósito general.
  3. **EX (Execute):** Cómputo en ALU entera o coprocesador de punto flotante.
  4. **MA (Memory Access):** Lectura o escritura en memoria de datos.
  5. **WB (Writeback):** Escritura del resultado en el banco de registros.
* Período de reloj: **$T_{clk} = 50\text{ ns}$** ($f = 20\text{ MHz}$).
* Banco de registros: $R_0$ a $R_{15}$ (donde $R_0 = 0$ cableado).

```
Pipeline Clásico TDA 1819:
[IF: Fetch] ---> [ID: Decode] ---> [EX: Execute] ---> [MA: MemAccess] ---> [WB: Writeback]
                      |                                                    |
                      +------- Banco de Registros (Lectura / Escritura) <--+
```

> **Notas para el orador:**
> * Explicar brevemente la estructura del pipeline de 5 etapas del TDA 1819.
> * Destacar que las lecturas de registros se realizan en la etapa ID y las escrituras efectivas recién en la etapa WB.
> * Esta separación temporal de 2 etapas completas entre ID y WB es la causa raíz de las dependencias de datos RAW.

---

<!-- slide -->
## DIAPOSITIVA 3: EL PROBLEMA ASIGNADO (PUNTO 4a)

### El Riesgo de Datos RAW (Read-After-Write) en el TDA 1819 Original
* **Escenario 4a:** Una instrucción ALU calcula un resultado en Execute que es necesitado inmediatamente como operando por la siguiente instrucción ALU.
* **Comportamiento original sin Forwarding:**
  - La entidad `raw_waw_detector` rastrea escrituras pendientes (`Rx_WrPending`).
  - Al detectar en ID que el registro fuente está pendiente, activa `StallRAW = '1'`.
  - **Penalización obligatoria:** **2 ciclos de burbuja (stalls)** por cada dependencia RAW ALU→ALU.

```
Cronograma sin Forwarding:
Ciclo:   1    2    3    4    5    6    7
I1:     [IF] [ID] [EX] [MA] [WB]
I2:          [IF] [ID] (STALL STALL) [ID] [EX] [MA] [WB]
                  ^-- Detecta RAW en ID (2 ciclos perdidos)
```

> **Notas para el orador:**
> * Mostrar con el diagrama cómo la instrucción $I_2$ se queda congelada en ID durante 2 ciclos.
> * Señalar la ineficiencia: el resultado de $I_1$ ya está listo en el Ciclo 3 al salir de la ALU, pero $I_2$ no puede usarlo hasta el Ciclo 6 porque espera a que pase por MA y WB.
> * El objetivo de nuestra implementación es permitir que $I_2$ continúe sin detenerse, tomando el resultado directamente de la ALU de $I_1$.

---

<!-- slide -->
## DIAPOSITIVA 4: ARQUITECTURA DE LA SOLUCIÓN

### La Técnica de Forwarding EX→EX
Consiste en un mecanismo coordinado de **dos acciones clave**:

```
                       +------------------------------------+
                       |           Forwarding EX->EX        |
                       |    (Resultado directo de la ALU)   |
                       +-----------------+------------------+
                                         |
                                         v
 [IF] ---> [ID] ------------------> [EX (ALU)] ---> [MA] ---> [WB]
            |                             ^
            |                             |
      raw_waw_detector               Multiplexor
  (Inhibe StallRAW si            (Sustituye op1/op2
   FwdCanResolve = true)          por PrevEXResult)
```

1. **Supresión selectiva del atasco en `raw_waw_detector`:**
   - Detecta si la dependencia corresponde al escenario 4a.
   - Si se cumple la condición, **no activa `StallRAW`**, permitiendo que la instrucción en Decode pase de inmediato a Execute.
2. **Cortocircuito (Multiplexor) en `execute.vhd`:**
   - Detecta si los operandos fuente coinciden con el registro destino previo (`PrevRd`).
   - Sustituye los operandos obsoletos por el resultado de la ALU previa (`PrevEXResult`).
3. **Control configurable:**
   - Generic `Forwarding : BOOLEAN := true` en toda la jerarquía para comparar con y sin adelantamiento.

> **Notas para el orador:**
> * Explicar que el adelantamiento no es solamente un cable entre etapas: requiere intervenir tanto en la lógica de detección de atascos (para no frenar el cauce) como en la etapa de ejecución (para conectar el dato correcto a las entradas de la ALU).
> * Resaltar que mantuvimos el generic `Forwarding` para poder reproducir exactamente el comportamiento original a demanda.

---

<!-- slide -->
## DIAPOSITIVA 5: MODIFICACIONES IMPLEMENTADAS EN VHDL

### 1. `tipos_cpu.vhd`
* Se extendió el registro `execute_record` con `id_rf`, `id_rg` e `id_rd` (identificadores de registros de 8 bits).

### 2. `decode.vhd`
* Se implementó la extracción de los IDs de registros para las **30 instrucciones ALU enteras** (17 Tipo A y 13 Tipo B).
* Se generó la señal `ID_is_ALU <= '1'` basada directamente en el código de operación (`CodOp`).

### 3. `execute.vhd`
* Se crearon las variables de estado previo: `PrevEXResult`, `PrevRd` y `PrevWasALU`.
* Se implementó el multiplexor de selección de operandos antes de invocar a la ALU.
* Se generaron las señales de estado `EX_is_ALU` y `EX_rd` conectadas al registro interno `IDtoEXALU`.

### 4. `raw_waw_detector.vhd`
* Se incorporó la condición `FwdCanResolve` dentro del procedimiento `CheckRAW`:
  $$FwdCanResolve := Forwarding \land (EX\_is\_ALU = '1') \land (ID\_is\_ALU = '1') \land (EX\_rd = IdRegID)$$
* Si `FwdCanResolve` es verdadero y hay una única escritura pendiente (`Rx_WrPending = 1`), **se inhibe `StallRAW`**.

> **Notas para el orador:**
> * Destacar la prolijidad en la modificación: se cubrieron las 30 instrucciones ALU del procesador (aritméticas, lógicas, desplazamientos y comparaciones).
> * Explicar que la propagación del generic `Forwarding` se realizó a través de `usuario.vhd`, `pc.vhd`, `cpu.vhd`, `etapas.vhd` y `atascos.vhd`.

---

<!-- slide -->
## DIAPOSITIVA 6: ASPECTOS CRÍTICOS DE SINCRONIZACIÓN Y DISEÑO

### Desafíos Técnicos Resueltos durante el Desarrollo

1. **Origen del registro destino en Execute (`IDtoEXALU` vs. `IDtoEX`):**
   - *Problema:* El puerto de entrada `IDtoEX` cambia apenas la siguiente instrucción entra a Decode.
   - *Solución:* Muestrear `EX_rd` y `EX_is_ALU` desde `IDtoEXALU`, que almacena la instrucción en ejecución real en la ALU.
2. **Prevención de carreras por ciclos delta en VHDL:**
   - *Problema:* Asignaciones concurrentes dependientes podían demorar 1 ciclo delta tras el flanco de reloj, haciendo que `raw_waw_detector` lea valores obsoletos.
   - *Solución:* Decodificación temprana de `ID_is_ALU` a partir de `CodOp` (estable 24 ns antes de la lectura de registros) y retardo de sincronización de 1 ns al caer el reloj.
3. **Reinicio seguro de variables de adelantamiento:**
   - Si la instrucción en Execute es un NOP, burbuja, acceso a memoria o FPU, `PrevWasALU` se fuerza inmediatamente a `false`, impidiendo adelantamientos indebidos en instrucciones no contiguas.
4. **Compilación y compatibilidad:**
   - Compilación limpia de los **38 archivos VHDL** con Aldec Active-HDL (`vcom.exe`) con **0 errores y 0 warnings**.

> **Notas para el orador:**
> * Esta diapositiva demuestra solidez en la ingeniería del proyecto: no fue una modificación superficial, sino que se analizaron y resolvieron problemas reales de simulación por eventos y ciclos delta en VHDL.
> * Destacar que se evitó cualquier posibilidad de corrupción de datos si en el medio hay una instrucción que no es de ALU.

---

<!-- slide -->
## DIAPOSITIVA 7: PROGRAMA DE PRUEBA 1 — `fwd_alu_cadena.asm`

### Cadena RAW Estricta Tipo A (Registro-Registro)
```asm
.data
NUM1: .word 10  |  NUM2: .word 20  |  RES1..4: .word 0
.code
lw r1, NUM1(r0)     ; r1 = 10
lw r2, NUM2(r0)     ; r2 = 20
; --- Cadena RAW ALU->ALU (Punto 4a) ---
dadd r3, r1, r2     ; r3 = 10 + 20 = 30  [Produce r3]
dadd r4, r3, r1     ; r4 = 30 + 10 = 40  [RAW en r3] -> FWD r3 (0 stalls)
dsub r5, r4, r2     ; r5 = 40 - 20 = 20  [RAW en r4] -> FWD r4 (0 stalls)
dmul r6, r5, r3     ; r6 = 20 * 30 = 600 [RAW en r5] -> FWD r5 (0 stalls)
sw r3, RES1(r0) ... sw r6, RES4(r0)
halt
```

### Comportamiento del Cauce con Forwarding:
```
Ciclo:  1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16
dadd r3:           [IF][STALL][ID][EX][MA][WB]
dadd r4:                      [IF][ID][EX][MA][WB]  <-- FWD r3 en ciclo 8
dsub r5:                          [IF][ID][EX][MA][WB]  <-- FWD r4 en ciclo 9
dmul r6:                              [IF][ID][EX][MA][WB]  <-- FWD r5 en ciclo 10
```

> **Notas para el orador:**
> * Explicar el código de prueba: 3 dependencias inmediatas consecutivas (`dadd` $\to$ `dadd` $\to$ `dsub` $\to$ `dmul`).
> * Destacar que el único atasco presente es el Load-Use entre `lw r2` y `dadd r3` (lo cual es correcto, ya que el escenario 4a no contempla carga de memoria, asignada al punto 4c).
> * En la cadena de ALU, las instrucciones fluyen a razón de 1 instrucción por ciclo.
> * Los resultados en memoria (`RES1=30`, `RES2=40`, `RES3=20`, `RES4=600`) confirman el cálculo exacto.

---

<!-- slide -->
## DIAPOSITIVA 8: PROGRAMA DE PRUEBA 2 — `fwd_alu_operaciones.asm`

### Mezcla de Instrucciones Tipo A y Tipo B (Inmediatos y Desplazamientos)
```asm
.data
VAL: .word 15  |  RES_A..C: .word 0
.code
lw r1, VAL(r0)       ; r1 = 15
; --- Dependencias Mixtas ALU->ALU ---
daddi r2, r1, 5      ; r2 = 15 + 5 = 20    [Tipo B: rd=r2, rf=r1, imm=5]
dsli  r3, r2, 2      ; r3 = 20 << 2 = 80   [Tipo B: rd=r3, rf=r2, imm=2] -> FWD r2
dadd  r4, r3, r2      ; r4 = 80 + 20 = 100  [Tipo A: rd=r4, rf=r3, rg=r2] -> FWD r3
andi  r5, r4, 255     ; r5 = 100 & 255 = 100[Tipo B: rd=r5, rf=r4, imm=255]-> FWD r4
sw r3, RES_A(r0) ... sw r5, RES_C(r0)
halt
```

### Aspectos Clave Validados:
* **Instrucciones Tipo B:** El operando adelantado se conecta correctamente a `op1` mientras que `op2` toma el inmediato sin ser perturbado.
* **Operandos Mixtos:** En `dadd r4, r3, r2`, el operando `r3` proviene de Forwarding y el operando `r2` proviene directamente del banco de registros ya actualizado.
* Resultados finales en memoria: `RES_A = 80`, `RES_B = 100`, `RES_C = 100`.

> **Notas para el orador:**
> * Justificar el segundo programa: demuestra que el adelantamiento no solo funciona con sumas de 3 registros, sino con inmediatos, desplazamientos lógicos (`dsli`) y operaciones booleanas (`andi`).
> * Reafirmar que esto cumple el requisito de tener al menos dos programas de prueba que contrasten el estado original frente al nuevo.

---

<!-- slide -->
## DIAPOSITIVA 9: RESULTADOS CUANTITATIVOS Y COMPARATIVA (PUNTO 3a)

### Tabla de Comparación de Rendimiento

| Métrica | No Segmentado (`Pipelining=false`) | Segmentado SIN FWD (`Forwarding=false`) | Segmentado CON FWD (`Forwarding=true`) | Impacto del Forwarding |
|---|---|---|---|---|
| **`fwd_alu_cadena.asm`** | | | | |
| Tiempo de Ensamblaje | 45 ns | 45 ns | 45 ns | 0 ns (Independiente) |
| Ciclos de Reloj Totales | 55 ciclos | 22 ciclos | **16 ciclos** | **-6 ciclos (-27.3%)** |
| Tiempo de Ejecución CPU | 2750 ns | 1100 ns | **800 ns** | **-300 ns de ahorro** |
| Atascos RAW ALU→ALU | 0 | 6 ciclos (3 $\times$ 2) | **0 ciclos** | **100% eliminados** |
| CPI (Ciclos por Instrucción) | 5.00 | 2.00 | **1.45** | **Mejora de 0.55 CPI** |
| Speedup vs No Segmentado | 1.00x | 2.50x | **3.44x** | **+37.6% sobre sin FWD** |
| **`fwd_alu_operaciones.asm`**| | | | |
| Ciclos de Reloj Totales | 45 ciclos | 20 ciclos | **14 ciclos** | **-6 ciclos (-30.0%)** |
| Tiempo de Ejecución CPU | 2250 ns | 1000 ns | **700 ns** | **-300 ns de ahorro** |
| CPI | 5.00 | 2.22 | **1.55** | **Mejora de 0.67 CPI** |
| Speedup vs No Segmentado | 1.00x | 2.25x | **3.21x** | **+42.7% sobre sin FWD** |

> **Notas para el orador:**
> * Explicar la distinción solicitada en el Punto 3a: el tiempo de ensamblaje (45 ns constantes) es la carga comportamental de memoria previa, mientras que el tiempo de CPU es la simulación física del cauce.
> * Destacar el impacto: en ambos programas se eliminaron exactamente 6 ciclos de atasco (3 riesgos RAW $\times$ 2 ciclos de burbuja).
> * La mejora neta de tiempo de CPU es de aproximadamente el 30%, reduciendo el CPI a valores cercanos al ideal teórico de 1.

---

<!-- slide -->
## DIAPOSITIVA 10: FLUJO DE EJECUCIÓN Y USO DE RECURSOS (PUNTO 3b)

### Actividad por Componente según la Etapa del Ciclo

| Componente | IF (Fetch) | ID (Decode) | EX (Execute) | MA (MemAccess) | WB (Writeback) |
|---|---|---|---|---|---|
| **Memoria Principal (Instrucciones)** | **Lectura** en dirección `IP`. Actualiza `IP`. | Inactiva. | Inactiva. | Inactiva. | Inactiva. |
| **Memoria Principal (Datos)** | Inactiva. | Inactiva. | Inactiva. | **Lectura** (`lw`) o **Escritura** (`sw`). | Inactiva. |
| **Memoria Principal (Pila)** | Inactiva. | Inactiva. | Inactiva. | Inactiva (sin push/pop). | Inactiva. |
| **Banco de Registros General** | Inactiva. | **Lectura** de operandos `rf` y `rg`. | Inactiva. | Inactiva. | **Escritura** del resultado en `rd`. |
| **Unidad Aritmético-Lógica (ALU)** | Inactiva. | Inactiva. | **Procesa** operación ALU o dirección de memoria. | Inactiva. | Inactiva. |
| **Registros de Estado / Flags** | Inactiva. | Inactiva. | **Actualiza** flags (`Z`, `S`, `O`, `C`). | Inactiva. | Inactiva. |
| **Detector de Atascos (`raw_waw`)** | Inactiva. | **Evalúa RAW:** si `FwdCanResolve`, mantiene `StallRAW='0'`. | Inactiva. | Inactiva. | Decrementa escrituras pendientes. |
| **Multiplexor de Forwarding** | Inactiva. | Inactiva. | **Inyecta** `PrevEXResult` en `op1`/`op2` si coincide con `PrevRd`. | Inactiva. | Inactiva. |

> **Notas para el orador:**
> * Explicar con esta tabla la respuesta al Punto 3b del enunciado: qué parte del hardware se lee, escribe o procesa en cada etapa.
> * Enfatizar cómo la etapa EX es la protagonista del adelantamiento (cálculo en ALU y multiplexor de entrada) y cómo la etapa ID interactúa con el detector de atascos.

---

<!-- slide -->
## DIAPOSITIVA 11: CONCLUSIONES GENERALES

### Resumen de Logros del Trabajo Práctico
1. **Cumplimiento estricto de las consignas:**
   - Se desarrolló en VHDL la funcionalidad 4a (Forwarding EX→EX ALU→ALU).
   - Se incorporó el generic `Forwarding` configurable en toda la jerarquía.
   - Se redactó el informe pormenorizado y se estructuró la presente defensa.
2. **Eficiencia probada del mecanismo:**
   - **100% de eliminación** de atascos RAW entre operaciones ALU consecutivas.
   - Reducción de hasta un **30% en el tiempo total de ejecución** de la CPU.
   - Preservación íntegra de la exactitud numérica en los resultados de memoria.
3. **Calidad y Robustez de Ingeniería:**
   - Prevención de condiciones de carrera por ciclos delta en simulación VHDL.
   - Cobertura de las 30 instrucciones ALU (enteras, inmediatas, desplazamientos y lógicas).
   - Compilación exitosa de la totalidad del proyecto (38/38 archivos) con **0 errores y 0 warnings**.

---

<!-- slide -->
## DIAPOSITIVA 12: ESPACIO PARA PREGUNTAS Y DEFENSA ORAL

### Muchas gracias por su atención.

**Estamos a disposición del tribunal docente para responder consultas técnicas y exhibir la simulación en Active-HDL.**

```
Archivos del proyecto disponibles para demostración:
* Informe detallado: Informe_TP10_TDA1819_Punto4a.md
* Código VHDL: tipos_cpu, decode, execute, raw_waw_detector, cpu, pc, usuario
* Código Assembly: fwd_alu_cadena.asm, fwd_alu_operaciones.asm
* Compilación: 100% OK en Aldec Active-HDL vcom
```
