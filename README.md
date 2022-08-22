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

Interest is determined by pool utilization rate following a x=yk curve capped at 80%, only owner can provide ETH for borrowing and, if any loans expire, NFTs are just transferred to pool owner.

## Key features
- Completely trustless, can't rug
- No liquidations
- Pay as you go
- Works for ultra smol/illiquid collections
- Variable rates

### Oracle
Traditional oracles like those used in all lending protocols are too expensive to operate because they continuously post prices on-chain and that makes the cost extremely high for an NFT that is likely to see very little borrowing volume. Furthermore, oracle networks are unlikely to build feeds for very small NFTs.

Our solution: 0-gas, on-request, trustless oracles that are self-run and which fail safely.

The way this works is that some server tracks minimum floor price for a configurable time period (eg: a week), and, when requested, signs a message with that price, which the user can submit on-chain to borrow ETH against that price.

After that initial borrow action, no oracle is used anymore, since all that is left is for user to just repay the loan before the deadline. But even when oracle is used to start the loan, no incorrect price can cause losses for user, who can also verify the price in UI. Thus the oracle doesn't require any trust at all from users' side. This is in stark contrast with most lending protocols, where an incorrect oracle update can cause everyone in lending market to lose money.

And if owner is the one operating the oracle, they just need to trust themselves, which is always true, so this means that effectively oracle is completely trustless.

On top of that, this oracle is extremely cheap to operate since it never needs to make any transaction, which also avoids all complexity of dealing with high gas, nonces... Only a regular web server is needed! And to top it off, it fails very safely, since if the server fails all that happens is that no new loans will be available until it's fixed, while in other lending protocols a stale oracle can cause protocol to be drained.

And even in the worst case scenario where server gets completely compromised and private key is leaked, there's a price ceiling that can be set by owner and which can block any attempts to steal owner's ETH by borrowing at inflated prices.

### Liquidations
From the users's point of view, their NFTs are extremely safe since:
- They can't be liquidated, user just needs to repay on time
- Even if they are liquidated, liquidator is collection owner that is incentivized to be friendly towards holders, so if liquidation was clearly a mistake it's easy to just talk with them and repay loan manually after liquidation.

Imo this is extremely important for NFTs since they are not directly replaceable, so if your nft gets liquidated you just can't get the same one back. Thus for NFT loans these extra asurances are important for users.

### LPing
Providing liquidity is extremely risky for highly illiquid collections without liquidation, so it would be quite hard to find people willing to LPs just for the fees. However, collection owners operate with a different set of incentives and for them it makes a lot of sense, since providing that perk to users increases collection value and they have substantial ETH bags allocated to providing value for holders.

Essentially a similar reason why defi projects provide liquidity for their own coin.

## Attacks
- Owner can withdraw liquidity to force rates to go up, but maximum they can go up is to 80% and loans are max 2 weeks, so at most this will lead to an increase of 3.3% in interest. Rate manipulation is also unlikely to happen cause it would stop people from using the market and destoy trust, the opposite of what you want as the collection owner.


## Developing
```shell
npm test
npx hardhat coverage
npx hardhat deploy --network rinkeby
npx hardhat etherscan-verify --network rinkeby
npx hardhat verify --network rinkeby DEPLOYED_CONTRACT_ADDRESS
```

## Some future ideas
- Rate limiting mechanism
- Allow anyone to LP
- Farming with underlying ETH?