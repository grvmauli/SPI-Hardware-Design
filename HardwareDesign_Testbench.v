module TB_HardwareDesign();
// AHB-Lite Bus Signals
	reg HCLK;					// AHB bus clock
	reg HRESETn;				// AHB reset signal Active low
	reg HSELx = 1'b0;			// Slave select signal will select the particular salve
	reg [31:0] HADDR = 32'h0;	// Address bus 32 bit
	reg [1:0] HTRANS = 2'b0;	// Type of transaction
	reg HWRITE = 1'b0;			// Operation type write or read
	reg [2:0] HSIZE = 3'b0;		// transaction width (max 32-bit supported)
	reg [31:0] HWDATA = 32'h0;	// write data
	reg [2:0] HBURST = 3'b0;	// burst type
	reg [3:0] HPROT = 4'b0011;	// privileged data transfer
	wire [31:0] HRDATA;			// read data from slave
	wire HREADY;				// The state of the transaction
    wire MOSI;					//Serial Output signal
	wire busy;            		//Status of the serial transmission
	wire MISO;					//Serial input signal
	
    //Defination for the transaction status
	localparam [1:0] IDLE = 2'b00, NONSEQ = 2'b10;
	//Selecting different address from the MUX for HRDATA
	localparam [31:0] TXdata = 32'h0,RXdata = 32'h4,status = 32'h8;
  
  
	// Instantiate the design under test and connect it to the testbench signals
  HardwareDesign#(.INCR (100)) dut(
		.HCLK(HCLK),
        .HRESETn(HRESETn),
		.HSEL(HSELx),
		.HREADY(HREADY),
		.HADDR(HADDR),
		.HTRANS(HTRANS),
		.HWRITE(HWRITE),   
		.HWDATA(HWDATA),  
		.HRDATA(HRDATA),  
		.HREADYOUT(HREADY),
        .busy (busy),       
		.MOSI (MOSI),
		.MISO (MISO),
		.SCLK(SCLK)
		);

	// Generation of clock signal at 50 MHz
	initial
		begin
			HCLK = 1'b0;
			forever
				#10 HCLK = ~HCLK;  // invert clock every 10 ns
		end
	assign MISO  = MOSI; 
	
	// Implementation of the verification Plan
	initial
		begin
			$dumpfile("dump.vcd"); 
      		$dumpvars;
			#20 HRESETn = 1'b0;				// AHB bus reset signal is reset intially with some time delay
			#20 HRESETn = 1'b1;				// reset signal  is made high as it is active low
			#200 AHBwrite(TXdata, 32'h85);	// Writing hex value of 85 , on address 0
            #500;							//Delay so that it can be seen in waveform
			AHBidle;						//Making the AHB bus idle
			#500;							// Delay for the next operation
          AHBread (status, 32'h1); 		//Reading the value from address 8 , Status of busy signal
			AHBidle;						//Making the AHB bus idle
			@(negedge busy);    			// wait for transmission to finish
            #500;							// Delay for the next operation
          AHBread (status, 32'h0); 		//Reading the value from address 8, Status of busy signal
			AHBidle;						//Making the AHB bus idle
          	#500;							// Delay for the next operation
          AHBread(RXdata, 32'h85);	//Reading the value from address 4 , Data in the RxReg
			AHBidle;
          #5000;             				// Delay to see all the scinario properly on waveform
            $finish(); 						// stop the simulation 
		end
		
	// Task to simulate a write transaction on AHB Lite
	reg [31:0] nextWdata = 32'h0;		// delayed data for write transactions
	reg [31:0] expectRdata = 32'h0;		// expected read data for read transactions
	reg [31:0] rExpectRead;				// store expected read data
	reg checkRead;						// remember that read is in progress
  
	reg error = 1'b0;  // read error signal - asserted for one cycle AFTER read completes
	integer errCount  = 0;	
	
	
	//The task to perform write on AHB lite Bus
	task AHBwrite ( 
			input [31:0] addr,		// Address on which data is to be written
			input [31:0] data );	// The Data that will be written on the address
		begin
			wait (HREADY == 1'b1);	// Wait until the HREADY signal becomes 1
			@ (posedge HCLK);	    // This will operate on positive edge of HCLK
			 #2HTRANS = NONSEQ;		// This will inform the type of transaction is Non sequential
			HWRITE = 1'b1;			//Write operation will get perform
			HADDR = addr;			// This will put the addresson the Bus
			HSELx = 1'b1;			// selecting the slave
			nextWdata = data;		// This will store and use data for next phase
		end
	endtask
	
	
	//The task to perform read on AHB lite Bus
	task AHBread (
			input [31:0] addr,		//Address on which data is to be read
			input [31:0] data );	//The Data that is epected from the slave
		begin  
			wait (HREADY == 1'b1);	// Wait until the previous bus transaction completes
			@ (posedge HCLK);		// This will operate on positive edge of HCLK
			HTRANS = NONSEQ;		// This will inform the type of transaction is Non sequential
			HWRITE = 1'b0;			//Read operation will get perform
			HADDR = addr;			// This will put the addresson the Bus
			HSELx = 1'b1;			// selecting the slave
			#1 expectRdata = data;	// This will store expected data for checking in the data phase
		end
	endtask
	
	
	//The task to put the AHB bus on idle state when not in use
	task AHBidle;
		begin  
			wait (HREADY == 1'b1); // Wait until the previous bus transaction completes
			@ (posedge HCLK);	  // This will operate on positive edge of HCLK
			#1 HTRANS = IDLE;	// The transaction is set to idle mode
			HSELx = 1'b0;		// All slaves are deselcted in idle mode
		end
	endtask
	
	
	// This will control the data to be transmitted on HWDATA
	always @ (posedge HCLK)				// This will operate on positive edge of HCLK
		if (~HRESETn) HWDATA <= 32'b0;	//HWDATA will reset when HRESETn is low 
		else if (HSELx && HWRITE && HTRANS && HREADY) // The write operation is moved to Data phase
			#1 HWDATA <= nextWdata;					// the HWDATA is changed with some delay
		else if (HREADY)							// some other transaction in progress
			#1 HWDATA <= HADDR;						// This will put the data present in the HADDR to HWDATA
			
	
	//during data phase rExpectRead will hold the read data
	//checkRead flag will indicate the status of read operation
	always @ (posedge HCLK)			// This will operate on positive edge of HCLK
		if (~HRESETn)				//operate When the HRESETn is low
			begin
				rExpectRead <= 32'b0;	//register will reset
				checkRead <= 1'b0;		//Flag will reset
			end
		else if (HSELx && ~HWRITE && HTRANS && HREADY)  // The Read operation is moved to Data phase
			begin
				rExpectRead <= expectRdata;	// the Register is updated with expected data
				checkRead <=1'b1;			// set the flag
			end
		else if (HREADY)					// some other transaction moving to data phase
				checkRead <= 1'b0;			// clear flag
	
	
// This will help to moniter if there is any error in the transaction
	always @ (posedge HCLK)				// This will operate on positive edge of HCLK
		if (~HRESETn) error <= 1'b0;
		else if (checkRead & HREADY)	// Checking the status of read operation
			if (HRDATA != rExpectRead)	// If the read data is not as per expected data
				begin
					error <= 1'b1;				// Error flag is set
					errCount = errCount + 1;	// Error counter will updated for each error
				end
			else error <= 1'b0;			//When there is not error error flag will reset
		else							//For scnario where error capture is not required
			error <= 1'b0;				//reset error flag


endmodule