from starkware.cairo.common.uint256 import Uint256

## Modify both functions so that they increment
## supplied value and return it
func add_one(y : felt) -> (val : felt):   
   return (y + 1) 
end

func add_one_U256{range_check_ptr}(y : Uint256) -> (val : Uint256):   
   alloc_locals
   local low = y.low + 1
   local high = y.high
   let val = Uint256(low, high)
   return (val) 
end
