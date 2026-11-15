
-- Entidad "execute":
-- Descripci�n: Aqu� se define el administrador para la etapa de ejecuci�n de la segmentaci�n 
-- del procesador, el cual recibe de la etapa de decodificaci�n	toda la informaci�n necesaria 
-- para poder trabajar: el tipo de operaci�n (nula, suma, resta, and, or, salto condicional, 
-- etc.) a realizar, el tipo de operandos (entero o punto flotante, con o sin signo) y los 
-- operandos propiamente dichos. Luego, si correspondiera, habilita en funci�n del tipo de 
-- operandos la unidad de ejecuci�n m�s adecuada: ALU (unidad aritm�tico-l�gica) para operandos
-- enteros o FPU (unidad de punto flotante) para operandos en punto flotante, y le proporciona 
-- exactamente la misma informaci�n recibida de la etapa "decode" para que pueda realizar la 
-- operaci�n aritm�tico-l�gica requerida. Finalmente, si es necesario env�a el resultado de la 
-- unidad habilitada al banco de registros internos para la segmentaci�n a fin de que �ste se 
-- encargue de transmitirlo a la etapa "writeback", la cual a su vez se ocupar� de escribirlo 
-- en el banco de registros del procesador. Cabe agregar que, mientras la ejecuci�n de una 
-- operaci�n en la ALU requiere un �nico ciclo de reloj para completarse, en la FPU, al ser m�s 
-- compleja, necesita cuatro ciclos para ser llevada a cabo sin importar su naturaleza (suma, 
-- resta, multiplicaci�n, divisi�n, etc.).
-- Procesos:
-- Main: En primer lugar, recibe la se�al del administrador de la CPU para comenzar la
-- etapa de ejecuci�n de una nueva instrucci�n. Luego, en la primera mitad del ciclo de
-- reloj comprueba si existen actualmente atascos de alg�n tipo en el cauce, deteniendo
-- temporalmente la ejecuci�n en caso afirmativo. Finalmente, en la segunda mitad del ciclo 
-- lleva a cabo la ejecuci�n propiamente dicha, habilitando la unidad de ejecuci�n que 
-- corresponda en funci�n del tipo de los operandos (o no habilitando ninguna en caso de que 
-- la instrucci�n no requiera la ejecuci�n de una operaci�n aritm�tico-l�gica) y 
-- proporcion�ndole la informaci�n recibida de la etapa "decode" para que pueda trabajar 
-- correctamente, y luego obteniendo el resultado devuelto por la misma para envi�rselo al 
-- banco de registros internos para la segmentaci�n.
-- Procedimientos y funciones:
-- InitializeIDtoEX(): Configura y carga toda la informaci�n inicial a enviar a las dos unidades 
-- disponibles, antes de que una de ellas sea modificada durante la ejecuci�n de esta etapa 
-- del pipeline: operaciones nulas, operandos y direcciones vac�as, etc.
-- InitializeAllIDtoEX(): Este procedimiento se invoca una �nica vez durante la primera 
-- ejecuci�n de este administrador para asignar valores iniciales v�lidos y nulos a todas sus 
-- se�ales internas auxiliares encargadas de almacenar informaci�n recibida de la etapa de
-- decodificaci�n a fin de que no ocurra ning�n inconveniente durante la ejecuci�n de la
-- simulaci�n por intentar leer se�ales que a�n no hayan sido previamente inicializadas.


library TDA_1819;
use TDA_1819.const_cpu.all;
use TDA_1819.const_flags.all;
use TDA_1819.tipos_cpu.all;

LIBRARY IEEE;

USE std.textio.all;
use ieee.NUMERIC_STD.all;
USE IEEE.std_logic_1164.all; 

library ieee_proposed;
use ieee_proposed.float_pkg.all;




entity execute is
	
	generic (
		Forwarding	: BOOLEAN := true);

	port ( 
		BranchEXALUtoSM		: out 	state_branch;
		DataRegInEXALU		: out 	std_logic_vector(31 downto 0);
		DataRegInEXFPU		: out 	std_logic_vector(31 downto 0);
		EnableRegEXALURd	: out 	std_logic;
		EnableRegEXFPURd	: out 	std_logic;
		EnableRegEXALUWr	: out 	std_logic;
		EnableRegEXFPUWr	: out 	std_logic;
		EnableRegEXALUIP	: out 	std_logic;
		EnableDecFPWrPend	: out 	std_logic;
		DataEXtoWB			: out 	std_logic_vector(31 downto 0);
		EnableCheckSTRM		: out 	std_logic;
		EXFPUPending		: out	std_logic;
		EnableEXALU			: inout std_logic;
		EnableEXFPU			: inout std_logic;
		StallSTR			: in  	std_logic;
		StallWAWAux			: in	std_logic;
		IDtoEX				: in  	execute_record;
		DataRegOutEXALU		: in  	std_logic_vector(31 downto 0);
		DataRegOutEXFPU		: in  	std_logic_vector(31 downto 0);
		EnableEX			: in  	std_logic;
		EX_rd				: out 	std_logic_vector(7 downto 0);
		EX_is_ALU			: out 	std_logic);

end execute;




architecture EXECUTE_ARCHITECTURE of execute is


	-- Component declaration of the tested unit
	component execute_alu
		port ( 
			BranchEXALUtoSM		: out state_branch;
			DataRegInEXALU		: out std_logic_vector(31 downto 0);
			EnableRegEXALURd	: out std_logic;
			EnableRegEXALUWr	: out std_logic;
			EnableRegEXALUIP	: out std_logic; 
			DoneEXALU			: out std_logic;
			DataEXALUtoWB		: out std_logic_vector(31 downto 0);
			IDtoEXALU			: in  execute_record;
			DataRegOutEXALU		: in  std_logic_vector(31 downto 0);
			EnableEXALU			: in  std_logic);
	end component;
	
	component execute_fpu
		port ( 
			DataRegInEXFPU		: out std_logic_vector(31 downto 0);
			EnableRegEXFPURd	: out std_logic;
			EnableRegEXFPUWr	: out std_logic;
			DoneEXFPU			: out std_logic;
			DataEXFPUtoWB		: out std_logic_vector(31 downto 0);
			IDtoEXFPU			: in  execute_record;
			DataRegOutEXFPU		: in  std_logic_vector(31 downto 0);
			EnableEXFPU			: in  std_logic);
	end component;
	
	
	FOR UUT1: execute_alu USE ENTITY WORK.execute_alu(execute_alu_architecture);
	FOR UUT2: execute_fpu USE ENTITY WORK.execute_fpu(execute_fpu_architecture);
		
	
	-- Add your code here ...	
	SIGNAL IDtoEXFPURecords:	execute_records(3 downto 0);
	SIGNAL DataEXALUtoWB: 		std_logic_vector(31 downto 0);
	SIGNAL DataEXFPUtoWB: 		std_logic_vector(31 downto 0);
	SIGNAL IDtoEXALU: 			execute_record;
	SIGNAL IDtoEXFPU: 			execute_record;	
	SIGNAL DoneEXALU:			std_logic;
	SIGNAL DoneEXFPU:			std_logic;
	
	
begin
	
	-- Forwarding 4a: senales hacia atascos/raw_waw_detector
	EX_is_ALU <= '1' when ((IDtoEXALU.fp = '0') and (to_integer(unsigned(IDtoEXALU.op)) /= EX_NULL) and (IDtoEXALU.id_rd /= "11111111")) else '0';
	EX_rd <= IDtoEXALU.id_rd;

	-- Unit Under Test port map
		
	UUT1: execute_alu
		port map (
			BranchEXALUtoSM		=> BranchEXALUtoSM,
			DataRegInEXALU		=> DataRegInEXALU,
			EnableRegEXALURd	=> EnableRegEXALURd,
			EnableRegEXALUWr	=> EnableRegEXALUWr,
			EnableRegEXALUIP	=> EnableRegEXALUIP,
			DoneEXALU			=> DoneEXALU,
			DataEXALUtoWB		=> DataEXALUtoWB,
			IDtoEXALU			=> IDtoEXALU,
			DataRegOutEXALU		=> DataRegOutEXALU,
			EnableEXALU			=> EnableEXALU);
	
	UUT2: execute_fpu
		port map (
			DataRegInEXFPU		=> DataRegInEXFPU,
			EnableRegEXFPURd	=> EnableRegEXFPURd,
			EnableRegEXFPUWr	=> EnableRegEXFPUWr,
			DoneEXFPU			=> DoneEXFPU,
			DataEXFPUtoWB		=> DataEXFPUtoWB,
			IDtoEXFPU			=> IDtoEXFPU,
			DataRegOutEXFPU		=> DataRegOutEXFPU,
			EnableEXFPU			=> EnableEXFPU);
	
			
	-- Add your stimulus here ...
	
	Main: PROCESS 
	
	PROCEDURE InitializeIDtoEX IS
	
	BEGIN 
		IDtoEXALU.op <= std_logic_vector(to_unsigned(EX_NULL, IDtoEXALU.op'length)); 
		IDtoEXALU.fp <= 'Z';
		IDtoEXALU.sign <= 'Z';
		IDtoEXALU.op1 <= "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";
		IDtoEXALU.op2 <= "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";
		IDtoEXALU.address <= "ZZZZZZZZZZZZZZZZ";
		IDtoEXALU.id_rf <= (others => '1');
		IDtoEXALU.id_rg <= (others => '1');
		IDtoEXALU.id_rd <= (others => '1');
		IDtoEXFPURecords(3).op <= std_logic_vector(to_unsigned(EX_NULL, IDtoEXFPURecords(3).op'length)); 
		IDtoEXFPURecords(3).fp <= 'Z';
		IDtoEXFPURecords(3).sign <= 'Z';
		IDtoEXFPURecords(3).op1 <= "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";
		IDtoEXFPURecords(3).op2 <= "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";
		IDtoEXFPURecords(3).address <= "ZZZZZZZZZZZZZZZZ";
	End InitializeIDtoEX;
	
	PROCEDURE InitializeAllIDtoEX IS
	
	BEGIN 
		IDtoEXALU.op <= std_logic_vector(to_unsigned(EX_NULL, IDtoEXALU.op'length)); 
		IDtoEXALU.fp <= 'Z';
		IDtoEXALU.sign <= 'Z';
		IDtoEXALU.op1 <= "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";
		IDtoEXALU.op2 <= "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";
		IDtoEXALU.address <= "ZZZZZZZZZZZZZZZZ";	
		IDtoEXALU.id_rf <= (others => '1');
		IDtoEXALU.id_rg <= (others => '1');
		IDtoEXALU.id_rd <= (others => '1');	
		for i in IDtoEXFPURecords'length-1 downto 0 loop
			IDtoEXFPURecords(i).op <= std_logic_vector(to_unsigned(EX_NULL, IDtoEXFPURecords(3).op'length)); 
			IDtoEXFPURecords(i).fp <= 'Z';
			IDtoEXFPURecords(i).sign <= 'Z';
			IDtoEXFPURecords(i).op1 <= "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";
			IDtoEXFPURecords(i).op2 <= "ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ";
			IDtoEXFPURecords(i).address <= "ZZZZZZZZZZZZZZZZ";
		end loop;
	End InitializeAllIDtoEX;
	
	VARIABLE First: BOOLEAN := true;
	VARIABLE Empty: STD_LOGIC;
	VARIABLE Op: INTEGER;			 
	VARIABLE Fp: STD_LOGIC;
	VARIABLE wasSTR: BOOLEAN := false;
	VARIABLE wasSTRW: BOOLEAN := false;
	VARIABLE varEXFPUPending: BOOLEAN := false;
	VARIABLE PrevEXResult: std_logic_vector(31 downto 0) := (others => '0');
	VARIABLE PrevRd: std_logic_vector(7 downto 0) := (others => '1');
	VARIABLE PrevWasALU: BOOLEAN := false;
	VARIABLE recordAux: execute_record;
	
	BEGIN 
		if (First) then
			First := false;
			EXFPUPending <= '0';
			EnableCheckSTRM <= '0';
			EnableDecFPWrPend <= '0'; 
			EnableEXALU <= '0'; 
			EnableEXFPU <= '0';
			InitializeAllIDtoEX;
			WAIT FOR 1 ns;
		end if;
		WAIT UNTIL rising_edge(EnableEX);
		EnableCheckSTRM <= '0';
		if (StallSTR = '1') then
			IDtoEXFPURecords(3) <= IDtoEXFPURecords(2);
			if (not wasSTR) then
				wasSTR := true;
			else
				wasSTR := false;
				InitializeIDtoEX;
			end if;
			WAIT FOR 2 ns;
			if (StallSTR = '0') then
				wasSTRW := true;
			end if;
		elsif (StallWAWAux = '1') then
			--for i in IDtoEXFPURecords'length-1 downto 2 loop
				--IDtoEXFPURecords(i) <= IDtoEXFPURecords(i-1);
			--end loop;
			--IDtoEXFPURecords(3) <= IDtoEXFPURecords(2);
			--InitializeIDtoEX;
			--WAIT UNTIL rising_edge(EnableEX);
			--WAIT UNTIL rising_edge(EnableEX);
			WAIT UNTIL falling_edge(StallWAWAux);
			DataEXtoWB <= DataEXALUtoWB;
			WAIT FOR 1 ns;
			if (StallSTR = '1') then
				WAIT UNTIL rising_edge(EnableEX);
				WAIT UNTIL rising_edge(EnableEX);
			else
				WAIT UNTIL rising_edge(EnableEX);
			end if;
		end if;
		EnableEXALU <= '1'; 
		EnableEXFPU <= '1';
		Op := to_integer(unsigned(IDtoEXFPURecords(1).op));
		if (Op /= EX_NULL) then
			EnableDecFPWrPend <= '1';
			WAIT FOR 1 ns;
			EnableDecFPWrPend <= '0';
		end if;	
		WAIT UNTIL falling_edge(EnableEX);
		InitializeIDtoEX;
		Empty := IDtoEX.empty;
		if (Empty = '0') then
			Fp := IDtoEX.fp;
			if (not wasSTRW) then
				if ((Fp = '0') or (Fp = 'Z')) then
					if (StallSTR = '0') then
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
						--WAIT FOR 1 ns;
					end if;
				else
					IDtoEXFPURecords(3) <= IDtoEX;
				end if;
			else
				wasSTRW := false;
			end if;
		end if;
		IDtoEXFPURecords(2) <= IDtoEXFPURecords(3);
		IDtoEXFPURecords(1) <= IDtoEXFPURecords(2);
		IDtoEXFPURecords(0) <= IDtoEXFPURecords(1);
		WAIT FOR 1 ns;
		for i in 1 to IDtoEXFPURecords'length-1 loop
			Op := to_integer(unsigned(IDtoEXFPURecords(i).op));
			if (Op /= EX_NULL) then
				varEXFPUPending := true;
				exit;
			end if;
		end loop;
		if (varEXFPUPending) then
			EXFPUPending <= '1';
			varEXFPUPending := false;
		else
			EXFPUPending <= '0';
		end if;
		Op := to_integer(unsigned(IDtoEXFPURecords(0).op));
		if (Op /= EX_NULL) then
			IDtoEXFPU <= IDtoEXFPURecords(0);
			EnableEXFPU <= '0';
			WAIT FOR 1 ns;
		end if;
		if ((StallSTR = '0') or (EnableEXFPU = '1')) then
			EnableCheckSTRM <= '1';
		end if;
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
		if (EnableEXFPU = '0') then
			if (DoneEXFPU = '0') then
				WAIT UNTIL rising_edge(DoneEXFPU);
			end if;
			DataEXtoWB <= DataEXFPUtoWB;
		end if;
		if ((EnableEXALU = '1') and (EnableEXFPU = '1')) then
			WAIT FOR 1 ns;
			if (StallSTR = '0') then
				DataEXtoWB <= DataEXALUtoWB;
			end if;
		end if;
	END PROCESS Main;
	
	
end EXECUTE_ARCHITECTURE;





