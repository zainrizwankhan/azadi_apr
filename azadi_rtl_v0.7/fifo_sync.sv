
// Generic synchronous fifo for use in a variety of devices.


module fifo_sync #(
  parameter int unsigned Width       = 16,
  parameter bit Pass                 = 1'b1, // if == 1 allow requests to pass through empty FIFO
  parameter int unsigned Depth       = 4,
  parameter bit OutputZeroIfEmpty    = 1'b1, // if == 1 always output 0 when FIFO is empty
  // derived parameter
  localparam int          DepthW     = tlul_pkg::vbits(Depth+1)
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,
  // synchronous clear / flush port
  input  logic                 clr_i,
  // write port
  input  logic                 wvalid_i,
  output logic                 wready_o,
  input  logic [Width-1:0]     wdata_i,
  // read port
  output logic                 rvalid_o,
  input  logic                 rready_i,
  output logic [Width-1:0]     rdata_o,
  // occupancy
  output logic [DepthW-1:0]    depth_o
);

  // FIFO is in complete passthrough mode
  if (Depth == 0) begin : gen_passthru_fifo

    assign depth_o = 1'b0; //output is meaningless

    // devie facing
    assign rvalid_o = wvalid_i;
    assign rdata_o = wdata_i;

    // host facing
    assign wready_o = rready_i;

    // this avoids lint warnings
    logic unused_clr;
    assign unused_clr = clr_i;

  // Normal FIFO construction
  end else begin : gen_normal_fifo

    localparam int unsigned PTRV_W    = tlul_pkg::vbits(Depth);
    localparam int unsigned PTR_WIDTH = PTRV_W+1;

    logic [PTR_WIDTH-1:0] fifo_wptr, fifo_rptr;
    logic                 fifo_incr_wptr, fifo_incr_rptr, fifo_empty;

    // create the write and read pointers
    logic  full, empty;
    logic  wptr_msb;
    logic  rptr_msb;
    logic  [PTRV_W-1:0] wptr_value;
    logic  [PTRV_W-1:0] rptr_value;

    assign wptr_msb = fifo_wptr[PTR_WIDTH-1];
    assign rptr_msb = fifo_rptr[PTR_WIDTH-1];
    assign wptr_value = fifo_wptr[0+:PTRV_W];
    assign rptr_value = fifo_rptr[0+:PTRV_W];
    assign depth_o = (full)                 ? DepthW'(Depth) :
                     (wptr_msb == rptr_msb) ? DepthW'(wptr_value) - DepthW'(rptr_value) :
                     (DepthW'(Depth) - DepthW'(rptr_value) + DepthW'(wptr_value)) ;

    assign fifo_incr_wptr = wvalid_i & wready_o;
    assign fifo_incr_rptr = rvalid_o & rready_i;

    assign wready_o = ~full;
    assign rvalid_o = ~empty;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        fifo_wptr <= {(PTR_WIDTH){1'b0}};
      end else if (clr_i) begin
        fifo_wptr <= {(PTR_WIDTH){1'b0}};
      end else if (fifo_incr_wptr) begin
        if (fifo_wptr[PTR_WIDTH-2:0] == (PTR_WIDTH-1)'(Depth-1)) begin
          fifo_wptr <= {~fifo_wptr[PTR_WIDTH-1],{(PTR_WIDTH-1){1'b0}}};
        end else begin
          fifo_wptr <= fifo_wptr + {{(PTR_WIDTH-1){1'b0}},1'b1};
        end
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        fifo_rptr <= {(PTR_WIDTH){1'b0}};
      end else if (clr_i) begin
        fifo_rptr <= {(PTR_WIDTH){1'b0}};
      end else if (fifo_incr_rptr) begin
        if (fifo_rptr[PTR_WIDTH-2:0] == (PTR_WIDTH-1)'(Depth-1)) begin
          fifo_rptr <= {~fifo_rptr[PTR_WIDTH-1],{(PTR_WIDTH-1){1'b0}}};
        end else begin
          fifo_rptr <= fifo_rptr + {{(PTR_WIDTH-1){1'b0}},1'b1};
        end
      end
    end

    assign  full       = (fifo_wptr == (fifo_rptr ^ {1'b1,{(PTR_WIDTH-1){1'b0}}}));
    assign  fifo_empty = (fifo_wptr ==  fifo_rptr);


    // the generate blocks below are needed to avoid lint errors due to array indexing
    // in the where the fifo only has one storage element
    logic [Depth-1:0][Width-1:0] storage;
    logic [Width-1:0] storage_rdata;
    if (Depth == 1) begin : gen_depth_eq1
      assign storage_rdata = storage[0];

      always_ff @(posedge clk_i)
        if (fifo_incr_wptr) begin
          storage[0] <= wdata_i;
        end
    // fifo with more than one storage element
    end else begin : gen_depth_gt1
      assign storage_rdata = storage[fifo_rptr[PTR_WIDTH-2:0]];

      always_ff @(posedge clk_i)
        if (fifo_incr_wptr) begin
          storage[fifo_wptr[PTR_WIDTH-2:0]] <= wdata_i;
        end
    end

    logic [Width-1:0] rdata_int;
    if (Pass == 1'b1) begin : gen_pass
      assign rdata_int = (fifo_empty && wvalid_i) ? wdata_i : storage_rdata;
      assign empty = fifo_empty & ~wvalid_i;
    end else begin : gen_nopass
      assign rdata_int = storage_rdata;
      assign empty = fifo_empty;
    end

    if (OutputZeroIfEmpty == 1'b1) begin : gen_output_zero
      assign rdata_o = empty ? 'b0 : rdata_int;
    end else begin : gen_no_output_zero
      assign rdata_o = rdata_int;
    end

  end // block: gen_normal_fifo



endmodule
