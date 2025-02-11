/* Absolute Value
 * Simple combinational item which produces absolute value
 */
module Abs(input signed [11:0] in, output signed [11:0] out);

	// If negative negate
	// Else don't change it (keep it positive)
	assign out = in > 0 ? in : -in;

endmodule