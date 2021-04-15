module HardwareDesign #( parameter INCR = 4'd4 ) ( //6.25Mbps data is transmitted
			// Bus signals
			input wire HCLK,			// AHB bus clock
			input wire HRESETn,			// AHB reset signal Active low
			input wire HSEL,			// Slave select signal will select the particular salve
			input wire HREADY,			// The state of the transaction
			input wire [31:0] HADDR,	// Address bus 32 bit
			input wire [1:0] HTRANS,	// Type of transaction
			input wire HWRITE,			// Operation type write or read
			input wire [31:0] HWDATA,	// Data to write
			output wire [31:0] HRDATA,	// It will read data from slave
			output wire HREADYOUT,		// Transaction status
			output reg MOSI,			//Serial Output signal
			input wire MISO,			//Serial input signal
            output reg SCLK,			// Serial Clock
			output busy 				//Status of the serial transmission
    );
	
	// Registers to hold signals from address phase
	reg [3:0] rHADDR;					//Trimmed lower 4 bits of the HADDR
	reg rWrite; 						//Signal 1 for write operation
	
	reg [15:0]	readData;
    reg [7:0] SPIOut;					// 8 bit data transmitted serially through MOSI
	reg [3:0] accum;					// Used for storing bit timing
	reg [7:0] temp = 8'b0;				// Temporary register the shift the parallel output of the 8 bit  receiver register
	reg [7:0] RxReg;					//Register the store the parallel output of the 8 bit serial in parallel out receiver register
	reg [3:0] bitCount;					// Count bits controls the Mux for the serail transmission of Data through MOSI
	
	wire load = rWrite & ~busy;			// signal tocontrol the multiplexer of the serial transmission counter
	wire  nextWrite = HSEL & HWRITE & HTRANS[1];// slave selected for write transfer
	
	//Serail in parallel out shift registers
	reg Reg_ff1;
	reg Reg_ff2;
	reg Reg_ff3;
	reg Reg_ff4;
	reg Reg_ff5;
	reg Reg_ff6;
	reg Reg_ff7;
	reg Reg_ff8;
	
	// Busy signal to show the status of the serail transmission
	assign busy = (bitCount != 4'd0);
	

	//In order to capture AHB bus and interanl signals
	always @(posedge HCLK)		//Operates at every positive edge of the HCLK
      if(~HRESETn)				//operates only when the HRESETn siganla is low
			begin
				rHADDR <= 4'b0;	//rHADDR will reset
				rWrite <= 1'b0; //rWrite will reset
			end
		else if(HREADY)       //Operates only when HREADY signal is high and busy is low means the serail transmission completed
             begin
                rHADDR <= HADDR[3:0];         //Stores the data of HADDR[3:0] into rHADDR
                rWrite <= nextWrite;		 //Stores the data of nextWrite into rWrite
             end
			 
	//Loading the lower 8 bit of HWDATA on write operation
	always @(posedge HCLK)		//Operates at every positive edge of the HCLK
      if(~HRESETn)				//Operates only when the HRESETn siganla is low
			begin
				SPIOut=8'b0;    //reset the value of SPIOut signal
			end
     else
		 begin		
				if ((rHADDR[3:2] == 2'h0)&& rWrite) SPIOut <= HWDATA[7:0];//The lower 8 bit of HWDATA is stored in SPIOut only when the write operation is selected
		 end
		
  //Loading data into HRDATA depending on rHADDR value
  always @(rHADDR,SPIOut,RxReg,busy)     //This will operate only when the value of the signals rHADDR,SPIOut,RxReg and busy signal
		case (rHADDR[3:2])		         // select the data on the basis of the 3rd and 2nd bit of the data in rHADDR
			2'h0:		readData = {8'b0,SPIOut};		// address ends in 0x0 - Transmitted data - Read/Write operation
			2'h1:		readData = {8'b0,RxReg};		// address ends in 0x4 - Received data   -  Read operation
			2'h2:		readData = {15'b0,busy};		// address ends in 0x8 - Status read			
		endcase
	assign HRDATA = {16'b0, readData};	// Output of the Mux is added with zero and given to HRDATA signal
	assign HREADYOUT = 1'b1;			// always ready - transaction never delayed
	
	
	//Serial clock Generation
	 always @ (posedge(HCLK))//Operates at every positive edge of the HCLK
		begin
          if (~HRESETn)		//Operates only when the HRESETn siganla is low
				SCLK <= 1'b0;	//Reset the SCLK signal
		  else if (Bitpulse  == 1)	//operates only when the Bitpulse value is 1
				SCLK <= ~SCLK & busy; //It will change the current state of the signal with the busy state of the signal
			else
				SCLK <= SCLK & busy; //Otherwise it will continue with the current state with status of Busy signal
		end
		

	// Generation od the Bitpulse signal
  wire [4:0] accSum = accum + INCR; // The value of the accum is added with INCR value
  wire Bitpulse  = accSum[4];      //Bitpulse will store the 4th bit of the of accum
	always @(posedge HCLK)			//Operates at every positive edge of the HCLK
      if (~HRESETn) accum <= 4'b0000; //reset the value in the accum
  else accum <= accSum[3:0];          //otherwise it will store the same value
  
  
  // Bit counter or state machine
	always @ (posedge HCLK)	//Operates at every positive edge of the HCLK
      if (~HRESETn) bitCount <= 4'd0; //It will reset the value of bit count
  else if (load) bitCount <= 4'd8;   //It will load the 8 value when load signal is high
  else if (Bitpulse  & busy & SCLK) bitCount <= bitCount-4'd1; //The value of the count is decreamented when Bitpulse,busy & SCLK are high
  
  
  
  // Sending the data through serail transmitter
   always @ (posedge(HCLK))	//Operates at every positive edge of the HCLK
     if(~HRESETn | ~busy ) MOSI<=1'b0; // reset the value of MOSI signal when HRESETn or busy signal is low
	always @ (bitCount or SPIOut)       //whenever the value of bitCount or SPIOut signal is updated
		case (bitCount)					//selection of the bit on the basis of bitcount value
          4'd8:		MOSI = SPIOut[7];
          4'd7:		MOSI = SPIOut[6];
          4'd6:		MOSI = SPIOut[5];
          4'd5:		MOSI = SPIOut[4];
          4'd4:		MOSI = SPIOut[3];
          4'd3:		MOSI = SPIOut[2];
          4'd2:		MOSI = SPIOut[1];
          4'd1:		MOSI = SPIOut[0];
			
		endcase
	
  
  //Receiver register data storage
  always @(posedge HCLK)	//Operates at every positive edge of the HCLK
    begin
	if (!HRESETn) //Operates only when the value of HRESETn i low
		begin
			//Reset all the value of register 
			Reg_ff1 <= 1'b0;
			Reg_ff2 <= 1'b0;
			Reg_ff3 <= 1'b0;
			Reg_ff4 <= 1'b0;
			Reg_ff5 <= 1'b0;
			Reg_ff6 <= 1'b0;
			Reg_ff7 <= 1'b0;
			Reg_ff8 <= 1'b0;
            temp = 8'b0;	  //reset the value of temporary storage register
          	RxReg=8'b0;		  // reset the receiver register
          	
		end
    else if(Bitpulse  & ~SCLK & busy) //Operates only Bitpulse and busy is high and SCLK is load
      begin
		//Serial inptut to the shift register
		Reg_ff1 <= MOSI;
		Reg_ff2 <= Reg_ff1;
		Reg_ff3 <= Reg_ff2;
		Reg_ff4 <= Reg_ff3;
		Reg_ff5 <= Reg_ff4;
		Reg_ff6 <= Reg_ff5;
		Reg_ff7 <= Reg_ff6;
		Reg_ff8 <= Reg_ff7;
		
        temp <= {temp[6:0],MISO}; //conveting 1 bit data into 8 bit data 
		assign RxReg =temp;		  // Storing it in the receiver register
      end
  end
endmodule