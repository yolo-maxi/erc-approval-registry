// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MockUniV3PositionManager {
    struct Position {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 fees0;
        uint256 fees1;
    }

    uint256 public nextTokenId = 1;
    mapping(uint256 tokenId => Position position) public positions;

    event PositionMinted(uint256 indexed tokenId, address indexed owner, uint128 liquidity);
    event LiquidityIncreased(uint256 indexed tokenId, uint128 amount);
    event FeesClaimed(uint256 indexed tokenId, address indexed recipient, uint256 amount0, uint256 amount1);

    function mint(address owner, int24 tickLower, int24 tickUpper, uint128 liquidity)
        external
        returns (uint256 tokenId)
    {
        tokenId = nextTokenId++;
        positions[tokenId] = Position({
            owner: owner,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity,
            fees0: 0,
            fees1: 0
        });
        emit PositionMinted(tokenId, owner, liquidity);
    }

    function increaseLiquidity(uint256 tokenId, uint128 amount) external {
        positions[tokenId].liquidity += amount;
        emit LiquidityIncreased(tokenId, amount);
    }

    function seedFees(uint256 tokenId, uint256 amount0, uint256 amount1) external {
        positions[tokenId].fees0 += amount0;
        positions[tokenId].fees1 += amount1;
    }

    function claim(uint256 tokenId, address recipient) external returns (uint256 amount0, uint256 amount1) {
        Position storage position = positions[tokenId];
        amount0 = position.fees0;
        amount1 = position.fees1;
        position.fees0 = 0;
        position.fees1 = 0;
        emit FeesClaimed(tokenId, recipient, amount0, amount1);
    }
}
