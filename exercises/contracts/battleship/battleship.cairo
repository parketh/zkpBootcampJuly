## I AM NOT DONE

%lang starknet
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256, uint256_le, uint256_unsigned_div_rem, uint256_sub
from starkware.starknet.common.syscalls import get_caller_address
from starkware.cairo.common.math import unsigned_div_rem, assert_le_felt, assert_le
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash_state import hash_init, hash_update 
from starkware.cairo.common.bitwise import bitwise_and, bitwise_xor


# SQUARE
#  - square_commit: hash of number at a given square
#  - square_reveal: revealed number at a given square
#  - shot: equal to 1 if square has been bombarded, 0 otherwise

struct Square:    
    member square_commit: felt
    member square_reveal: felt
    member shot: felt
end


# PLAYER
#  - address: address of the player
#  - points: number of points scored by player (4 to win)
#  - [UNUSED] revealed: number of squares revealed by the player

struct Player:    
    member address: felt
    member points: felt
    member revealed: felt
end


# GAME
#  - player1: Player struct representing player 1
#  - player2: Player struct representing player 2
#  - next_player: equal to 1 if player 1's turn is next, 2 otherwise
#  - last_move: tuple containing x, y location of last move
#  - winner: equal to 1 if player 1 has won, 2 if player 2 has won, 0 otherwise

struct Game:        
    member player1: Player
    member player2: Player
    member next_player: felt
    member last_move: (x: felt, y: felt)
    member winner: felt
end


# GRID
#  - game_idx: game index
#  - player: address of player
#  - x, y: position on board

@storage_var
func grid(game_idx : felt, player : felt, x : felt, y : felt) -> (square : Square):
end


# GAMES
#  - game_idx: game index
#  - game_struct: Game

@storage_var
func games(game_idx : felt) -> (game_struct : Game):
end


# GAME_COUNTER
#  - game_counter: current game number

@storage_var
func game_counter() -> (game_counter : felt):
end


# HASHES NUMBER
#  - Accepts number as input
#  - Returns Pedersen hash of number

func hash_numb{pedersen_ptr : HashBuiltin*}(numb : felt) -> (hash : felt):
    alloc_locals
    let (local array : felt*) = alloc()
    assert array[0] = numb
    assert array[1] = 1
    let (hash_state_ptr) = hash_init()
    let (hash_state_ptr) = hash_update{hash_ptr=pedersen_ptr}(hash_state_ptr, array, 2)   
    tempvar pedersen_ptr :HashBuiltin* = pedersen_ptr       
    return (hash_state_ptr.current_hash)
end


# SETS UP GAME
#  - Accepts two player addresses (felts) as input
#  - Reads current game index from game_counter 
#  - Creates struct Game with addresses of the players, all params initialised to zero
#  - Writes values to games mapping
#  - Increments game_counter by one

@external
func set_up_game{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(player1 : felt, player2 : felt):
    alloc_locals
    let (current_idx) = game_counter.read()

    let p1 = Player(player1, 0, 0)
    let p2 = Player(player2, 0, 0)
    let new_game = Game(p1, p2, 0, (0, 0), 0)

    games.write(current_idx, new_game)
    game_counter.write(current_idx + 1)

    return ()
end


# CHECKS IF CALLER IS ONE OF THE TWO PLAYERS
#  - Accepts caller addresses (felt) and current game (Game) as input
#  - Returns true if caller is one of the players and false otherwise

@view 
func check_caller{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(caller : felt, game : Game) -> (valid : felt):
    if caller == game.player1.address:
        return (1)
    end 

    if caller == game.player2.address:
        return (1)
    end

    return (0)
end


# CHECK IF SHIP WAS HIT
#  - Accepts square_commit (felt) and square_reveal (felt) as input
#  - Re-hashes square_reveal and compares it to square_commit
#  - Returns true if the two match, and false otherwise

@view
func check_hit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(square_commit : felt, square_reveal : felt) -> (hit : felt):
    alloc_locals
    let (hash) = hash_numb(square_reveal)
    let (q, r) = uint256_unsigned_div_rem(Uint256(square_reveal,  0), Uint256(2, 0))

    if square_commit == hash:
        if r.low == 1:
            return(1)
        else:
            return(0)
        end
    else:
        return(0)
    end
end


# INVOKES BOMBARDMENT
#  - Accepts as input:
#    > game index (felt)
#    > x (felt), y (felt) denominating position to hit
#    > square_reveal (felt), containing attempted reveal for the square to bombard
#  - Checks whether caller is one of the players 
#  - Checks whether it is their turn to move
#  - Call check_hit and update square
#  - If hit has been made, increment score for the player and update player
#  - If player has accumulated four points, declare them a winner
#  - Update game struct to reflect changes in player points, next player and last move

@external
func bombard{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(game_idx : felt, x : felt, y : felt, square_reveal : felt):
    alloc_locals
    let (caller_address) = get_caller_address()
    let (game) = games.read(game_idx)
    let curr_player = game.next_player

    # Checks whether caller is one of the players 
    let (valid) = check_caller(caller_address, game)
    if valid == 0:
        return ()
    end

    # Checks whether it is their move
    if curr_player != caller_address and game.last_move.x + game.last_move.y != 0:
        return ()
    end

    # Call check_hit
    let (square) = grid.read(game_idx, caller_address, x, y)
    tempvar square_commit = square.square_commit
    let (hit) = check_hit(square_commit, square_reveal)
    let updated_square = Square(square_commit, square_reveal, 1)
    grid.write(game_idx, caller_address, x, y, updated_square)

    # If hit has been made, increment score for the player and update player
    local player1: Player = game.player1
    local player2: Player = game.player2
    local next_move: (felt, felt) = (x, y)
    local winner: felt = 0
    
    if curr_player == player1.address:
        local updated_player1: Player = Player(player1.address, player1.points + hit, 0)
        if player1.points + hit == 4:
            winner = curr_player
        end
        local updated_game: Game = Game(updated_player1, player2, 2, next_move, winner)
        games.write(game_idx, updated_game)
    else:
        local updated_player2: Player = Player(player2.address, player2.points + hit, 0)
        if player2.points + hit == 4:
            winner = curr_player
        end
        local updated_game: Game = Game(player1, updated_player2, 1, next_move, winner)
        games.write(game_idx, updated_game)
    end
    
    return ()
end


# ADD MASKED SHIP POSITIONS
#  - Accepts as input:
#    > idx (felt): WHAT IS THIS??
#    > game_idx (felt): game index
#    > hashes_len (felt): length of array of hashes submitted
#    > hashes (felt*): array of hashes
#    > player (felt): address of player adding the squares
#    > x (felt), y (felt): WHAT ARE THESE FOR?
#  - Checks whether caller is one of the players
#  - (?) Check that no moves have been taken yet
#  - Call load_hashes to iterate over hashes array and submit each hash under the correct mapping index

@external
func add_squares{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(idx : felt, game_idx : felt, hashes_len : felt, hashes : felt*, player : felt, x: felt, y: felt):
    alloc_locals
    let (caller_address) = get_caller_address()
    let (game) = games.read(game_idx)

    let (valid) = check_caller(caller_address, game)
    if valid == 0:
        return ()
    end

    load_hashes(idx, game_idx, hashes_len, hashes, player, x, y)

    return ()
end


# LOAD SHIP POSITIONS
#  - Accepts as input:
#    > idx (felt): WHAT IS THIS??
#    > game_idx (felt): game index
#    > hashes_len (felt): length of array of hashes submitted
#    > hashes (felt*): array of hashes
#    > player (felt): address of player adding the squares
#    > x (felt), y (felt): WHAT ARE THESE FOR?
#  - Load hash into squares in the grid mapping
#  - Recursively call load_hashes until all hashes have been placed

func load_hashes{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(idx : felt, game_idx : felt, hashes_len : felt, hashes : felt*, player : felt, x: felt, y: felt):
    alloc_locals
    if hashes_len == 0:
        return ()
    end

    let (q, r) = uint256_unsigned_div_rem(Uint256(hashes_len,  0), Uint256(5, 0))
    tempvar x_loc = r.low
    tempvar y_loc = q.low

    let new_square = Square(hashes[hashes_len - 1], 0, 0)

    grid.write(game_idx, player, x_loc, y_loc, new_square)
    load_hashes(idx, game_idx, hashes_len - 1, hashes, player, x, y)
    
    return ()
end
