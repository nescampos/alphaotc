contract AlphaOTC {
    use dep::aztec::{
        protocol_types::{abis::function_selector::FunctionSelector, address::AztecAddress, traits::Serialize},
        state_vars::{PublicImmutable, SharedImmutable}
    };
    use dep::token::Token;

    #[aztec(event)]
    struct WithdrawalProcessed {
        who: AztecAddress,
        amount: u64,
        token: AztecAddress
    }

    #[aztec(event)]
    struct AgreementCancelled {
        who: AztecAddress
    }

    #[aztec(storage)]
    struct Storage {
        // Token used for the source counterparty
        source_token: PublicImmutable<AztecAddress>,
        // Amount for the token used for the source counterparty
        source_amount: PublicImmutable<u64>,
        // Source counterparty address
        source_address: SharedImmutable<AztecAddress>,
        // Token used for the destination counterparty
        destination_token: PublicImmutable<AztecAddress>,
        // Amount for the token used for the destination counterparty
        destination_amount: PublicImmutable<u64>,
        // Destination counterparty address
        destination_address: SharedImmutable<AztecAddress>,
        source_deposited: PublicImmutable<bool>,
        destination_deposited: PublicImmutable<bool>,
        money_withdrawn_from_source : PublicImmutable<bool>,
        money_withdrawn_from_destination : PublicImmutable<bool>,
        agreement_cancelled : PublicImmutable<bool>,
    }

    #[aztec(public)]
    #[aztec(initializer)]
    fn init(source_token: AztecAddress,source_amount: u64, destination_token: AztecAddress,destination_amount: u64, deadline: u64) {
        storage.source_token.initialize(source_token);
        storage.source_amount.initialize(source_amount);
        storage.destination_token.initialize(destination_token);
        storage.destination_amount.initialize(destination_amount);
        storage.source_deposited.initialize(false);
        storage.destination_deposited.initialize(false);
        storage.money_withdrawn_from_source.initialize(false);
        storage.money_withdrawn_from_destination.initialize(false);
        storage.agreement_cancelled.initialize(false);
        storage.source_address.initialize(context.msg_sender());
    }

    #[aztec(public)]
    #[aztec(internal)]
    fn _check_source_token_deposited() {
        let deposited = storage.source_deposited.read();
        assert(deposited == false, "Source tokens was deposited");
    }

    #[aztec(public)]
    #[aztec(internal)]
    fn _check_destination_token_deposited() {
        let deposited = storage.destination_deposited.read();
        assert(deposited == false, "Destination tokens was deposited by the counterparty");
    }

    #[aztec(private)]
    fn send_source_tokens() {

        AlphaOTC::at(context.this_address())._check_source_token_deposited().static_enqueue(&mut context);
        // Send the source tokens to the contract
        Token::at(storage.source_token.read()).transfer(
            context.msg_sender(),
            context.this_address(),
            storage.source_amount.read() as Field,
            0
        ).call(&mut context);

        storage.source_deposited.write(true);
    }

    #[aztec(private)]
    fn send_destination_tokens() {

        AlphaOTC::at(context.this_address())._check_destination_token_deposited().static_enqueue(&mut context);

        let source_address = storage.source_address.read_private();
        assert(context.msg_sender() == source_address, "Your are the other counterparty, source, you cannot send tokens here");

        let deposited_by_destination = storage.destination_deposited.read();
        assert(deposited_by_destination == false, "There is already an interested party who deposited their tokens in this agreement");
        // Send the destination tokens to the contract
        Token::at(storage.destination_token.read()).transfer(
            context.msg_sender(),
            context.this_address(),
            storage.destination_amount.read() as Field,
            0
        ).call(&mut context);

        storage.destination_deposited.write(true);

        storage.destination_address.write(context.msg_sender());
    }

    #[aztec(private)]
    fn withdraw_from_source() {
        let deposited_by_source = storage.source_deposited.read();
        let deposited_by_destination = storage.destination_deposited.read();
        assert(deposited_by_source == true && deposited_by_destination == true, "Both you and a counterparty must deposit your tokens in order to withdraw your part of the agreement");


        let source_address = storage.source_address.read_private();
        assert(context.msg_sender() == source_address, "You are not the source counterparty");

        let agreement_cancelled = storage.agreement_cancelled.read();
        assert(agreement_cancelled == false, "The agreement was cancelled.");

        let withdrawn = storage.money_withdrawn_from_source.read();
        assert(withdrawn == false, "You already withdrew the money");

        // Transfer the destination tokens to the source address (buyer)
        let amount = storage.destination_amount.read();
        let destination_token = storage.destination_token.read();
        Token::at(destination_token).transfer(context.this_address(), source_address, amount as Field, 0).call(&mut context);

        storage.money_withdrawn_from_source.write(true);
        // Emit an unencrypted event so that anyone can audit how much the source address has withdrawn
        let event = WithdrawalProcessed { amount, who: source_address, token: destination_token };
        context.emit_unencrypted_log(event.serialize());
    }

    #[aztec(private)]
    fn withdraw_from_destination() {
        let deposited_by_source = storage.source_deposited.read();
        let deposited_by_destination = storage.destination_deposited.read();
        assert(deposited_by_source == true && deposited_by_destination == true, "Both you and a counterparty must deposit your tokens in order to withdraw your part of the agreement");


        let destination_address = storage.destination_address.read_private();
        assert(context.msg_sender() == destination_address, "You are not the destination counterparty");

        let agreement_cancelled = storage.agreement_cancelled.read();
        assert(agreement_cancelled == false, "The agreement was cancelled.");

        let withdrawn = storage.money_withdrawn_from_destination.read();
        assert(withdrawn == false, "You already withdrew the money");

        // Transfer the source tokens to the destination address (buyer)
        let amount = storage.source_amount.read();
        let source_token = storage.source_token.read();
        Token::at(source_token).transfer(context.this_address(), destination_address, amount as Field, 0).call(&mut context);

        storage.money_withdrawn_from_destination.write(true);
        // Emit an unencrypted event so that anyone can audit how much the destination address has withdrawn
        let event = WithdrawalProcessed { amount, who: destination_address, token: source_token };
        context.emit_unencrypted_log(event.serialize());
    }

    #[aztec(private)]
    fn cancel_agreement_from_source() {

        let source_address = storage.source_address.read_private();
        assert(context.msg_sender() == source_address, "You are not the source counterparty");

        let deposited_by_source = storage.source_deposited.read();
        assert(deposited_by_source == true, "You haven't deposited your tokens, so you can't cancel the agreement");

        let withdrawn = storage.money_withdrawn_from_destination.read();
        assert(withdrawn == false, "The money has already been withdrawn, you cannot cancel");

        let deposited_by_destination = storage.destination_deposited.read();
        let destination_address = storage.destination_address.read_private();

        let source_token = storage.source_token.read();
        let destination_token = storage.destination_token.read();

        // Check if the counterparty deposited their tokens, adding a 0.5% penalty if so for canceling in this instance
        // Send the tokens back to the recipient (and if there is a penalty, that goes to the other party as compensation).
        if deposited_by_destination == true {
            let penalty = storage.source_amount.read() * 0.005; // 0.5% as penalty
            let amount = storage.source_amount.read() - penalty; 
            Token::at(source_token).transfer(context.this_address(), source_address, amount as Field, 0).call(&mut context);
            Token::at(source_token).transfer(context.this_address(), destination_address, penalty as Field, 0).call(&mut context);
        }
        else {
            let amount = storage.source_amount.read(); // without penalty
            Token::at(source_token).transfer(context.this_address(), source_address, amount as Field, 0).call(&mut context);
        }
        let destination_amount = storage.destination_amount.read();
        Token::at(destination_token).transfer(context.this_address(), destination_address, destination_amount as Field, 0).call(&mut context);

        storage.agreement_cancelled.write(true);
        
        // Emit an unencrypted event so that anyone can audit the source address cancelled this agreement
        let event = AgreementCancelled { who: source_address};
        context.emit_unencrypted_log(event.serialize());
    }

    #[aztec(private)]
    fn cancel_agreement_from_destination() {

        let destination_address = storage.destination_address.read_private();
        assert(context.msg_sender() == destination_address, "You are not the destination counterparty");

        let deposited_by_destination= storage.destination_deposited.read();
        assert(deposited_by_destination == true, "You haven't deposited your tokens, so you can't cancel the agreement");

        let withdrawn = storage.money_withdrawn_from_source.read();
        assert(withdrawn == false, "The money has already been withdrawn, you cannot cancel");

        let deposited_by_source = storage.source_deposited.read();
        let source_address = storage.source_address.read_private();

        let source_token = storage.source_token.read();
        let destination_token = storage.destination_token.read();

        // Check if the counterparty deposited their tokens, adding a 0.5% penalty if so for canceling in this instance
        // Send the tokens back to the recipient (and if there is a penalty, that goes to the other party as compensation).
        if deposited_by_source == true {
            let penalty = storage.destination_amount.read() * 0.005; // 0.5% as penalty
            let amount = storage.destination_amount.read() - penalty; 
            Token::at(destination_token).transfer(context.this_address(), destination_address, amount as Field, 0).call(&mut context);
            Token::at(destination_token).transfer(context.this_address(), source_address, penalty as Field, 0).call(&mut context);
        }
        else {
            let amount = storage.destination_amount.read(); // without penalty
            Token::at(destination_token).transfer(context.this_address(), destination_address, amount as Field, 0).call(&mut context);
        }
        let source_amount = storage.source_amount.read();
        Token::at(source_token).transfer(context.this_address(), source_address, source_amount as Field, 0).call(&mut context);

        storage.agreement_cancelled.write(true);
        
        // Emit an unencrypted event so that anyone can audit the destination address cancelled this agreement
        let event = AgreementCancelled { who: destination_address};
        context.emit_unencrypted_log(event.serialize());
    }


}