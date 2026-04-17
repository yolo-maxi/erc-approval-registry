// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract MockUniV3PositionManager {
    struct Position {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 tokensOwed0;
        uint256 tokensOwed1;
    }

    uint256 public nextTokenId = 1;
    mapping(uint256 tokenId => Position position) public positions;

    event Minted(uint256 indexed tokenId, address indexed owner, int24 tickLower, int24 tickUpper, uint128 liquidity);
    event LiquidityIncreased(uint256 indexed tokenId, uint128 amount);
    event FeesCollected(uint256 indexed tokenId, address indexed recipient, uint256 amount0, uint256 amount1);

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
            tokensOwed0: 0,
            tokensOwed1: 0
        });
        emit Minted(tokenId, owner, tickLower, tickUpper, liquidity);
    }

    function seedFees(uint256 tokenId, uint256 amount0, uint256 amount1) external {
        Position storage p = positions[tokenId];
        p.tokensOwed0 += amount0;
        p.tokensOwed1 += amount1;
    }

    function increaseLiquidity(uint256 tokenId, uint128 amount) external {
        positions[tokenId].liquidity += amount;
        emit LiquidityIncreased(tokenId, amount);
    }

    function collect(uint256 tokenId, address recipient) external returns (uint256 amount0, uint256 amount1) {
        Position storage p = positions[tokenId];
        amount0 = p.tokensOwed0;
        amount1 = p.tokensOwed1;
        p.tokensOwed0 = 0;
        p.tokensOwed1 = 0;
        emit FeesCollected(tokenId, recipient, amount0, amount1);
    }
}
