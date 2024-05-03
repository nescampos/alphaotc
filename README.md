# Alpha OTC

dApp with Aztec Network for OTC markets.

## Process

1. Source wallet creates the agreement, with source and destination tokens, and amounts.
2. Source wallet deposits its tokens in the contract and wait for a buyer.
3. Destination wallet (buyer) deposits its token (specified in the contract, step 1).
4. Source and destination wallets can withdraw their new tokens.
5. If source wallet cancels the agreement, gets its original tokens back (with a 0.5% penalty for the counterparty if they had deposited their part, with no penalty if the counterparty did not deposit theirs).
6. If destination wallet cancels the agreement, gets its original tokens back (with a 0.5% penalty for the counterparty if they had deposited their part, with no penalty if the counterparty did not deposit theirs).
