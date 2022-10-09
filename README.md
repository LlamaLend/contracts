# NFT-collateralized loans for long tail markets
Deposit NFTs and borrow ETH for small illiquid NFT collections that can't get into the main NFT lending markets.

## Why?
Being able to obtain liquidity for NFTs is an extremely important service for NFT holders, since atm, if a holder needs liquid money because a good opportunity has appeared, all they can do is just sell their NFTs.

This has multiple ramifications:
- People are less likely to buy into a collection long-term because they are afraid of being illiquid later.
- If a person associates their identity with an NFT and they sell it because they need liquidity, they are unlikely to be able to buy the same NFT back and rejoin the collection, thus it loses a heavily engaged member.
- Having this service be available to major collections but not small ones further concentrates wealth on the top ones, a process that is already happening and which makes small collections less viable.
- Knowing that in the future you might have to sell your NFT if you need liquidity makes you less likely to want to associate your identity with that NFT, which works against the collection

But for small collections getting access to borrowing liquidity is extremely difficult:
- They'll never get accepted into the major lending pools because risk is shared
- Running isolated pools is very complex
    - Atm no protocol offers these at all
    - Would need LPs, but providing borrowing liquidity to small and illiquid collection has extreme risks and barely nobody will want to LP
    - Needs oracles but chainlink wont provide a feed because of costs and running your own feed is very complicated and makes the whole project ruggable
    - Need robust liquidation bots, which are really hard to make reliably (even maker liquidation bots failed) and which people are unlikely to build because opportunity is low in small markets like this and it involves high risk since atomic arbs are not available for most small collections, so arbing this requires taking MM risk, which is extremely high for small and illiquid NFTs.
    - Borrowing against the NFT you use for your identity is dangerous in case it gets liquidated by mistake.

We tackle all these problems by exploiting a market structure present in lots of NFT collections: the team conducting the sale owns a lot of ETH and is interested in offering lending services to holders for the reasons explained above.

## How does it work?
Users can deposit their NFTs, get a signed price attestation from a server, and borrow 1/3rd of the floor value of these NFTs in ETH. Then they have up to 2 weeks to repay the loan, but they can repay at any time and will only be charged interest for the time used. 

Interest is fixed at loan creation and is determined by pool utilization rate, only owner can provide ETH for borrowing and, if any loans expire, NFTs are just transferred to pool owner.

## Key features
- Completely trustless, can't rug
- No liquidations
- Pay as you go
- Works for ultra smol/illiquid collections
- Fixed rates based on pool utilization

### Oracle
Traditional oracles like those used in all lending protocols are too expensive to operate because they continuously post prices on-chain and that makes the cost extremely high for an NFT that is likely to see very little borrowing volume. Furthermore, oracle networks are unlikely to build feeds for very small NFTs.

Our solution: 0-gas, on-request, trustless oracles that are self-run and which fail safely.

The way this works is that some server tracks minimum floor price for a configurable time period (eg: a week), and, when requested, signs a message with that price, which the user can submit on-chain to borrow ETH against that price.

After that initial borrow action, no oracle is used anymore, since all that is left is for user to just repay the loan before the deadline. But even when oracle is used to start the loan, no incorrect price can cause losses for user, who can also verify the price in UI. Thus the oracle doesn't require any trust at all from users' side. This is in stark contrast with most lending protocols, where an incorrect oracle update can cause everyone in lending market to lose money.

And if owner is the one operating the oracle, they just need to trust themselves, which is always true, so this means that effectively oracle is completely trustless.

On top of that, this oracle is extremely cheap to operate since it never needs to make any transaction, which also avoids all complexity of dealing with high gas, nonces... Only a regular web server is needed! And to top it off, it fails very safely, since if the server fails all that happens is that no new loans will be available until it's fixed, while in other lending protocols a stale oracle can cause protocol to be drained.

And even in the worst case scenario where server gets completely compromised and private key is leaked, there's a price ceiling that can be set by owner and which can block any attempts to steal owner's ETH by borrowing at inflated prices.

For more info on oracle methodology and how we prevent price manipulation check [our oracle docs](https://github.com/LlamaLend/oracle).

### Liquidations
From the users's point of view, their NFTs are extremely safe since:
- They can't be liquidated, user just needs to repay on time
- Even if they are liquidated, liquidator is collection owner that is incentivized to be friendly towards holders, so if liquidation was clearly a mistake it's easy to just talk with them and repay loan manually after liquidation.

Imo this is extremely important for NFTs since they are not directly replaceable, so if your nft gets liquidated you just can't get the same one back. Thus for NFT loans these extra asurances are important for users.

However, friendly liquidations are not enforced in the protocol, and they are completely up to the LP. So what I think will end up happening is that we'll see multiple LPs that compete in this market: mercenary LPs that insta liquidate you but offer 40% interest and other LPs that won't insta-liquidate you but who will charge you 80% interest. This will just be a free market and we aim to support everyone through our modular liquidation system.

#### Modular liquidations
LlamaLend pools don't come with a built-in liquidation system, instead pool owner can attach any liquidation system they want.

Here are some examples:
- If you want to prioritize dumping NFTs as fast as possible and avoiding any bad debt, you can just allow anyone to liquidate an expired loan by providing the amount borrowed.
- If you want to maximize amount earned from liquidated NFTs you could run an english or dutch auction on them, with proceeds going to pool owner, borrower, or both.
- If you want to make it easier for your users to get their NFT back you could implement low late fees, extended repayment plans, manual off-chain liquidations...

The system is extremely flexible and can implement any liquidation logic that people want to use.

### LPing
Providing liquidity is extremely risky for highly illiquid collections without liquidation, so it would be quite hard to find people willing to LPs just for the fees. However, collection owners operate with a different set of incentives and for them it makes a lot of sense, since providing that perk to users increases collection value and they have substantial ETH bags allocated to providing value for holders.

Essentially a similar reason why defi projects provide liquidity for their own coin.

### Late repayment fees
An issue I found multiple times with the previous iteration of llamalend is that people like to wait till the literal last second to repay, and that means that it's quite common that their loan expires a few seconds before their repay, meaning that you have to liquidate them. This is quite bothersome and not a great user experience so I introduced late fees: after a loan has expired you can still repay it but you need to pay an extra late fee that increases linearly by 100% of borrowed amount every 24h. In other words, from the moment a loan expires we start charging an extra interest of 36,500%.

The goal of this is not to charge that insane interest but to provide a way for users that are slightly late (eg up to a few hours) to still repay their loan, moving repayment from a cliff to a steep slope instead.

## Attacks
- A MEV bot can sandwitch txs by borrowing max before and repaying max after, making txs revert. No reason for doing this other than annoying users (at cost to mev bot) and it's easy to solve by using a private mempool.

## Risks for LPs
- You are selling put options on NFTs, if NFT price drops >66% before some loan expires, user will likely not repay and you'll get the NFT at a loss.
- Contracts could have a bug
- Oracle could have a bug or key could be leaked, which would allow hackers to borrow at any price below the on-chain price limit you have set.
- Oracle could be manipulated by inflating price for a week or by manipulating our data sources, which would make it possible to borrow for incorrect prices up to on-chain price limit.

## Admin powers
Factory owner (which is me, 0xngmi) can trigger emergencyShutdown(), a function that will prevent new loans from being created. This is meant to be used in case we identify a bug or if oracle is compromised.

That's the only admin function llamalend has, and this function doesnt affect in any way loan repayments, deposits or withdrawals, just stops new loans, meaning that it's impossible to use this function to rug.

## Developing

Copy `.env.example`, updating `PRIVATEKEY` and setting a value for `ETHERSCAN` (if you want to verify).

```shell
npm install --save-dev
npm test
npx hardhat deploy --network rinkeby
npx hardhat etherscan-verify --network rinkeby
npx hardhat verify --network rinkeby DEPLOYED_CONTRACT_ADDRESS
```

## Some future ideas
- Allow anyone to LP
