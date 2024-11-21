import { describe, it, expect, beforeEach, vi } from "vitest";

describe("WagerWise Contract - Mocked Tests", () => {
  let contractState;

  beforeEach(() => {
    // Reset contract state before each test
    contractState = {
      markets: new Map(), // { marketId: { creator, description, options, ... } }
      bets: new Map(), // { `${marketId}-${address}-${option}`: { amount, claimedAmount } }
      optionTotals: new Map(), // { `${marketId}-${option}`: { totalAmount } }
      marketNonce: 0,
    };
  });

  const createMarket = (creator, description, options, endBlock) => {
    if (!description || options.length === 0 || endBlock <= 0) {
      throw new Error("ERR_INVALID_INPUT");
    }
    const marketId = contractState.marketNonce;
    contractState.markets.set(marketId, {
      creator,
      description,
      options,
      endBlock,
      totalBets: 0,
      isSettled: false,
      winningOption: null,
    });
    contractState.marketNonce += 1;
    return marketId;
  };

  const placeBet = (marketId, address, option, amount) => {
    const market = contractState.markets.get(marketId);
    if (!market) throw new Error("ERR_NOT_FOUND");
    if (market.endBlock <= 0 || market.isSettled) throw new Error("ERR_MARKET_ACTIVE");
    if (option < 0 || option >= market.options.length || amount <= 0) {
      throw new Error("ERR_INVALID_INPUT");
    }

    // Update bet
    const betKey = `${marketId}-${address}-${option}`;
    const bet = contractState.bets.get(betKey) || { amount: 0, claimedAmount: 0 };
    bet.amount += amount;
    contractState.bets.set(betKey, bet);

    // Update option total
    const optionKey = `${marketId}-${option}`;
    const optionTotal = contractState.optionTotals.get(optionKey) || { totalAmount: 0 };
    optionTotal.totalAmount += amount;
    contractState.optionTotals.set(optionKey, optionTotal);

    // Update market total
    market.totalBets += amount;
  };

  const settleMarket = (marketId, address, winningOption) => {
    const market = contractState.markets.get(marketId);
    if (!market) throw new Error("ERR_NOT_FOUND");
    if (market.creator !== address) throw new Error("ERR_UNAUTHORIZED");
    if (market.isSettled) throw new Error("ERR_ALREADY_SETTLED");
    if (winningOption < 0 || winningOption >= market.options.length) {
      throw new Error("ERR_INVALID_INPUT");
    }

    market.isSettled = true;
    market.winningOption = winningOption;
  };

  const calculateWinnings = (marketId, option, betAmount) => {
    const market = contractState.markets.get(marketId);
    const optionKey = `${marketId}-${option}`;
    const optionTotal = contractState.optionTotals.get(optionKey);
    if (!market || !optionTotal) throw new Error("ERR_NOT_FOUND");

    return Math.floor((market.totalBets * betAmount) / optionTotal.totalAmount);
  };

  const claimPartialWinnings = (marketId, address, option, amountToClaim) => {
    const market = contractState.markets.get(marketId);
    const betKey = `${marketId}-${address}-${option}`;
    const bet = contractState.bets.get(betKey);
    if (!market || !bet) throw new Error("ERR_NOT_FOUND");
    if (!market.isSettled || market.winningOption !== option) throw new Error("ERR_UNAUTHORIZED");

    const totalClaimable = bet.amount;
    const alreadyClaimed = bet.claimedAmount;
    if (alreadyClaimed + amountToClaim > totalClaimable) {
      throw new Error("ERR_INSUFFICIENT_BALANCE");
    }

    const winnings = calculateWinnings(marketId, option, amountToClaim);
    bet.claimedAmount += amountToClaim;

    if (bet.claimedAmount === bet.amount) {
      contractState.bets.delete(betKey); // Remove fully claimed bet
    }

    return winnings;
  };

  // Mocked Tests
  it("should create a new market successfully", () => {
    const marketId = createMarket(
      "deployer",
      "Will it rain tomorrow?",
      ["Yes", "No"],
      100
    );

    expect(marketId).toBe(0);
    expect(contractState.markets.get(marketId)).toEqual({
      creator: "deployer",
      description: "Will it rain tomorrow?",
      options: ["Yes", "No"],
      endBlock: 100,
      totalBets: 0,
      isSettled: false,
      winningOption: null,
    });
  });

  it("should place a bet successfully", () => {
    const marketId = createMarket(
      "deployer",
      "Will it rain tomorrow?",
      ["Yes", "No"],
      100
    );

    placeBet(marketId, "user1", 1, 500);

    const betKey = `${marketId}-user1-1`;
    expect(contractState.bets.get(betKey)).toEqual({ amount: 500, claimedAmount: 0 });

    const optionKey = `${marketId}-1`;
    expect(contractState.optionTotals.get(optionKey)).toEqual({ totalAmount: 500 });
    expect(contractState.markets.get(marketId).totalBets).toBe(500);
  });

  it("should fail to place a bet on an invalid market", () => {
    expect(() => placeBet(99, "user1", 1, 500)).toThrowError("ERR_NOT_FOUND");
  });

  it("should settle a market successfully", () => {
    const marketId = createMarket(
      "deployer",
      "Will it rain tomorrow?",
      ["Yes", "No"],
      100
    );

    settleMarket(marketId, "deployer", 1);

    expect(contractState.markets.get(marketId).isSettled).toBe(true);
    expect(contractState.markets.get(marketId).winningOption).toBe(1);
  });

  it("should calculate winnings correctly", () => {
    const marketId = createMarket(
      "deployer",
      "Will it rain tomorrow?",
      ["Yes", "No"],
      100
    );

    placeBet(marketId, "user1", 1, 500);
    placeBet(marketId, "user2", 1, 500);

    const winnings = calculateWinnings(marketId, 1, 250);
    expect(winnings).toBe(250); // Winnings should scale proportionally
  });

  it("should claim partial winnings", () => {
    const marketId = createMarket(
      "deployer",
      "Will it rain tomorrow?",
      ["Yes", "No"],
      100
    );

    placeBet(marketId, "user1", 1, 500);
    settleMarket(marketId, "deployer", 1);

    const winnings = claimPartialWinnings(marketId, "user1", 1, 250);
    expect(winnings).toBe(250);

    const betKey = `${marketId}-user1-1`;
    expect(contractState.bets.get(betKey).claimedAmount).toBe(250);
  });
});
