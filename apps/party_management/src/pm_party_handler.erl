-module(pm_party_handler).

-include_lib("damsel/include/dmsl_payment_processing_thrift.hrl").

%% Woody handler called by pm_woody_wrapper

-behaviour(pm_woody_wrapper).

-export([handle_function/3]).

%%

-spec handle_function(woody:func(), woody:args(), pm_woody_wrapper:handler_opts()) ->
    term()| no_return().

handle_function(Func, Args, Opts) ->
    scoper:scope(partymgmt,
        fun() -> handle_function_(Func, Args, Opts) end
    ).

-spec handle_function_(woody:func(), woody:args(), pm_woody_wrapper:handler_opts()) ->
    term()| no_return().

%% Party

handle_function_('Create', [UserInfo, PartyID, PartyParams], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    pm_party_machine:start(PartyID, PartyParams);

handle_function_('Checkout', [UserInfo, PartyID, RevisionParam], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    checkout_party(PartyID, RevisionParam, #payproc_InvalidPartyRevision{});

handle_function_('Get', [UserInfo, PartyID], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    pm_party_machine:get_party(PartyID);

handle_function_('GetRevision', [UserInfo, PartyID], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    pm_party_machine:get_last_revision(PartyID);

handle_function_('GetStatus', [UserInfo, PartyID], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    pm_party_machine:get_status(PartyID);

handle_function_(Fun, [UserInfo, PartyID | _Tail] = Args, _Opts) when
    Fun =:= 'Block' orelse
    Fun =:= 'Unblock' orelse
    Fun =:= 'Suspend' orelse
    Fun =:= 'Activate'
->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    call(PartyID, Fun, Args);

%% Contract

handle_function_('GetContract', [UserInfo, PartyID, ContractID], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    Party = pm_party_machine:get_party(PartyID),
    ensure_contract(pm_party:get_contract(ContractID, Party));

handle_function_('ComputeContractTerms', Args, _Opts) ->
    [UserInfo, PartyID, ContractID, Timestamp, PartyRevisionParams, DomainRevision, Varset] = Args,
    ok = set_meta_and_check_access(UserInfo, PartyID),
    Party = checkout_party(PartyID, PartyRevisionParams),
    Contract = ensure_contract(pm_party:get_contract(ContractID, Party)),
    VS0 = #{
        party_id => PartyID,
        identification_level => get_identification_level(Contract, Party)
    },
    VS1 = prepare_varset(PartyID, Varset, VS0),
    Terms = pm_party:get_terms(Contract, Timestamp, DomainRevision),
    pm_party:reduce_terms(Terms, VS1, DomainRevision);

%% Shop

handle_function_('GetShop', [UserInfo, PartyID, ID], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    Party = pm_party_machine:get_party(PartyID),
    ensure_shop(pm_party:get_shop(ID, Party));

handle_function_('ComputeShopTerms', [UserInfo, PartyID, ShopID, Timestamp, PartyRevision], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    Party = checkout_party(PartyID, pm_maybe:get_defined(PartyRevision, {timestamp, Timestamp})),
    Shop = ensure_shop(pm_party:get_shop(ShopID, Party)),
    Contract = pm_party:get_contract(Shop#domain_Shop.contract_id, Party),
    Revision = pm_domain:head(),
    VS = #{
        party_id => PartyID,
        shop_id  => ShopID,
        category => Shop#domain_Shop.category,
        currency => (Shop#domain_Shop.account)#domain_ShopAccount.currency,
        identification_level => get_identification_level(Contract, Party)
    },
    pm_party:reduce_terms(pm_party:get_terms(Contract, Timestamp, Revision), VS, Revision);

handle_function_(Fun, [UserInfo, PartyID | _Tail] = Args, _Opts) when
    Fun =:= 'BlockShop' orelse
    Fun =:= 'UnblockShop' orelse
    Fun =:= 'SuspendShop' orelse
    Fun =:= 'ActivateShop'
->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    call(PartyID, Fun, Args);

%% Wallet

handle_function_('ComputeWalletTermsNew', [UserInfo, PartyID, ContractID, Timestamp, Varset], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    Party = checkout_party(PartyID, {timestamp, Timestamp}),
    Contract = pm_party:get_contract(ContractID, Party),
    Revision = pm_domain:head(),
    VS0 = #{
        identification_level => get_identification_level(Contract, Party)
    },
    VS1 = prepare_varset(PartyID, Varset, VS0),
    pm_party:reduce_terms(pm_party:get_terms(Contract, Timestamp, Revision), VS1, Revision);

%% Claim

handle_function_('GetClaim', [UserInfo, PartyID, ID], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    pm_party_machine:get_claim(ID, PartyID);

handle_function_('GetClaims', [UserInfo, PartyID], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    pm_party_machine:get_claims(PartyID);

handle_function_(Fun, [UserInfo, PartyID | _Tail] = Args, _Opts) when
    Fun =:= 'CreateClaim' orelse
    Fun =:= 'AcceptClaim' orelse
    Fun =:= 'UpdateClaim' orelse
    Fun =:= 'DenyClaim' orelse
    Fun =:= 'RevokeClaim'
->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    call(PartyID, Fun, Args);

%% Event

handle_function_('GetEvents', [UserInfo, PartyID, Range], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    #payproc_EventRange{'after' = AfterID, limit = Limit} = Range,
    pm_party_machine:get_public_history(PartyID, AfterID, Limit);

%% ShopAccount

handle_function_('GetAccountState', [UserInfo, PartyID, AccountID], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    Party = pm_party_machine:get_party(PartyID),
    pm_party:get_account_state(AccountID, Party);

handle_function_('GetShopAccount', [UserInfo, PartyID, ShopID], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    Party = pm_party_machine:get_party(PartyID),
    pm_party:get_shop_account(ShopID, Party);

%% Providers

handle_function_('ComputeP2PProvider', Args, _Opts) ->
    [UserInfo, P2PProviderRef, DomainRevision, Varset] = Args,
    ok = assume_user_identity(UserInfo),
    Provider = get_p2p_provider(P2PProviderRef, DomainRevision),
    VS = prepare_varset(Varset),
    pm_provider:reduce_p2p_provider(Provider, VS, DomainRevision);

handle_function_('ComputeWithdrawalProvider', Args, _Opts) ->
    [UserInfo, WithdrawalProviderRef, DomainRevision, Varset] = Args,
    ok = assume_user_identity(UserInfo),
    Provider = get_withdrawal_provider(WithdrawalProviderRef, DomainRevision),
    VS = prepare_varset(Varset),
    pm_provider:reduce_withdrawal_provider(Provider, VS, DomainRevision);

handle_function_('ComputePaymentProvider', Args, _Opts) ->
    [UserInfo, PaymentProviderRef, DomainRevision, Varset] = Args,
    ok = assume_user_identity(UserInfo),
    Provider = get_payment_provider(PaymentProviderRef, DomainRevision),
    VS = prepare_varset(Varset),
    pm_provider:reduce_payment_provider(Provider, VS, DomainRevision);

handle_function_('ComputePaymentProviderTerminalTerms', Args, _Opts) ->
    [UserInfo, PaymentProviderRef, TerminalRef, DomainRevision, Varset] = Args,
    ok = assume_user_identity(UserInfo),
    Provider = get_payment_provider(PaymentProviderRef, DomainRevision),
    Terminal = get_terminal(TerminalRef, DomainRevision),
    VS = prepare_varset(Varset),
    pm_provider:reduce_payment_provider_terminal_terms(Provider, Terminal, VS, DomainRevision);

%% PartyMeta

handle_function_('GetMeta', [UserInfo, PartyID], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    pm_party_machine:get_meta(PartyID);

handle_function_('GetMetaData', [UserInfo, PartyID, NS], _Opts) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    pm_party_machine:get_metadata(NS, PartyID);

handle_function_(Fun, [UserInfo, PartyID | _Tail] = Args, _Opts) when
    Fun =:= 'SetMetaData' orelse
    Fun =:= 'RemoveMetaData'
->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    call(PartyID, Fun, Args);

%% Payment Institutions

handle_function_(
    'ComputePaymentInstitutionTerms',
    [UserInfo, PartyID, PaymentInstitutionRef, Varset],
    _Opts
) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    Revision = pm_domain:head(),
    PaymentInstitution = get_payment_institution(PaymentInstitutionRef, Revision),
    VS = prepare_varset(PartyID, Varset),
    ContractTemplate = get_default_contract_template(PaymentInstitution, VS, Revision),
    Terms = pm_party:get_terms(ContractTemplate, pm_datetime:format_now(), Revision),
    pm_party:reduce_terms(Terms, VS, Revision);

%% Payouts adhocs

handle_function_(
    'ComputePayoutCashFlow',
    [UserInfo, PartyID, #payproc_PayoutParams{id = ShopID, amount = Amount, timestamp = Timestamp} = PayoutParams],
    _Opts
) ->
    ok = set_meta_and_check_access(UserInfo, PartyID),
    Party = checkout_party(PartyID, {timestamp, Timestamp}),
    Shop = ensure_shop(pm_party:get_shop(ShopID, Party)),
    Contract = pm_party:get_contract(Shop#domain_Shop.contract_id, Party),
    Currency = Amount#domain_Cash.currency,
    ok = pm_currency:validate_currency(Currency, Shop),
    PayoutTool = get_payout_tool(Shop, Contract, PayoutParams),
    VS = #{
        party_id => PartyID,
        shop_id  => ShopID,
        category => Shop#domain_Shop.category,
        currency => Currency,
        cost     => Amount,
        payout_method => pm_payout_tool:get_method(PayoutTool)
    },
    Revision = pm_domain:head(),
    case pm_party:get_terms(Contract, Timestamp, Revision) of
        #domain_TermSet{payouts = PayoutsTerms} when PayoutsTerms /= undefined ->
            compute_payout_cash_flow(Amount, PayoutsTerms, Shop, Contract, VS, Revision);
        #domain_TermSet{payouts = undefined} ->
            throw(#payproc_OperationNotPermitted{})
    end.

%%

call(PartyID, FunctionName, Args) ->
    pm_party_machine:call(PartyID, party_management, {'PartyManagement', FunctionName}, Args).

%%

get_payout_tool(_Shop, Contract, #payproc_PayoutParams{payout_tool_id = ToolID})
    when ToolID =/= undefined
->
    case pm_contract:get_payout_tool(ToolID, Contract) of
        undefined ->
            throw(#payproc_PayoutToolNotFound{});
        PayoutTool ->
            PayoutTool
    end;
get_payout_tool(Shop, Contract, _PayoutParams) ->
    pm_contract:get_payout_tool(Shop#domain_Shop.payout_tool_id, Contract).

set_meta_and_check_access(UserInfo, PartyID) ->
    ok = assume_user_identity(UserInfo),
    _ = set_party_mgmt_meta(PartyID),
    assert_party_accessible(PartyID).

-spec assert_party_accessible(
    dmsl_domain_thrift:'PartyID'()
) ->
    ok | no_return().

assert_party_accessible(PartyID) ->
    UserIdentity = pm_woody_handler_utils:get_user_identity(),
    case pm_access_control:check_user(UserIdentity, PartyID) of
        ok ->
            ok;
        invalid_user ->
            throw(#payproc_InvalidUser{})
    end.

set_party_mgmt_meta(PartyID) ->
    scoper:add_meta(#{party_id => PartyID}).

assume_user_identity(UserInfo) ->
    pm_woody_handler_utils:assume_user_identity(UserInfo).

checkout_party(PartyID, RevisionParam) ->
    checkout_party(PartyID, RevisionParam, #payproc_PartyNotExistsYet{}).

checkout_party(PartyID, RevisionParam, Exception) ->
    try
        pm_party_machine:checkout(PartyID, RevisionParam)
    catch
        error:revision_not_found ->
            throw(Exception)
    end.

ensure_contract(#domain_Contract{} = Contract) ->
    Contract;
ensure_contract(undefined) ->
    throw(#payproc_ContractNotFound{}).

ensure_shop(#domain_Shop{} = Shop) ->
    Shop;
ensure_shop(undefined) ->
    throw(#payproc_ShopNotFound{}).

get_payment_institution(PaymentInstitutionRef, Revision) ->
    case pm_domain:find(Revision, {payment_institution, PaymentInstitutionRef}) of
        #domain_PaymentInstitution{} = P ->
            P;
        notfound ->
            throw(#payproc_PaymentInstitutionNotFound{})
    end.

get_p2p_provider(P2PProviderRef, DomainRevision) ->
    try
        pm_domain:get(DomainRevision, {p2p_provider, P2PProviderRef})
    catch
        error:{object_not_found, {DomainRevision, {p2p_provider, P2PProviderRef}}} ->
            throw(#payproc_ProviderNotFound{})
    end.

get_withdrawal_provider(WithdrawalProviderRef, DomainRevision) ->
    try
        pm_domain:get(DomainRevision, {withdrawal_provider, WithdrawalProviderRef})
    catch
        error:{object_not_found, {DomainRevision, {withdrawal_provider, WithdrawalProviderRef}}} ->
            throw(#payproc_ProviderNotFound{})
    end.

get_payment_provider(PaymentProviderRef, DomainRevision) ->
    try
        pm_domain:get(DomainRevision, {provider, PaymentProviderRef})
    catch
        error:{object_not_found, {DomainRevision, {provider, PaymentProviderRef}}} ->
            throw(#payproc_ProviderNotFound{})
    end.

get_terminal(TerminalRef, DomainRevision) ->
    try
        pm_domain:get(DomainRevision, {terminal, TerminalRef})
    catch
        error:{object_not_found, {DomainRevision, {terminal, TerminalRef}}} ->
            throw(#payproc_TerminalNotFound{})
    end.

get_default_contract_template(#domain_PaymentInstitution{default_contract_template = ContractSelector}, VS, Revision) ->
    ContractTemplateRef = pm_selector:reduce_to_value(ContractSelector, VS, Revision),
    pm_domain:get(Revision, {contract_template, ContractTemplateRef}).

compute_payout_cash_flow(
    Amount,
    #domain_PayoutsServiceTerms{fees = CashFlowSelector},
    Shop,
    Contract,
    VS,
    Revision
) ->
    Cashflow = pm_selector:reduce_to_value(CashFlowSelector, VS, Revision),
    CashFlowContext = #{operation_amount => Amount},
    Currency = Amount#domain_Cash.currency,
    AccountMap = collect_payout_account_map(Currency, Shop, Contract, VS, Revision),
    pm_cashflow:finalize(Cashflow, CashFlowContext, AccountMap).

collect_payout_account_map(
    Currency,
    #domain_Shop{account = ShopAccount},
    #domain_Contract{payment_institution = PaymentInstitutionRef},
    VS,
    Revision
) ->
    PaymentInstitution = get_payment_institution(PaymentInstitutionRef, Revision),
    SystemAccount = pm_payment_institution:get_system_account(Currency, VS, Revision, PaymentInstitution),
    #{
        {merchant , settlement} => ShopAccount#domain_ShopAccount.settlement,
        {merchant , guarantee } => ShopAccount#domain_ShopAccount.guarantee,
        {merchant , payout    } => ShopAccount#domain_ShopAccount.payout,
        {system   , settlement} => SystemAccount#domain_SystemAccount.settlement,
        {system   , subagent  } => SystemAccount#domain_SystemAccount.subagent
    }.

prepare_varset(#payproc_Varset{} = V) ->
    prepare_varset(undefined, V).

prepare_varset(PartyID, #payproc_Varset{} = V) ->
    prepare_varset(PartyID, V, #{}).

prepare_varset(PartyID, #payproc_Varset{} = V, VS0) ->
    genlib_map:compact(VS0#{
        party_id => PartyID,
        category => V#payproc_Varset.category,
        currency => V#payproc_Varset.currency,
        cost => V#payproc_Varset.amount,
        payment_tool => prepare_payment_tool_var(V#payproc_Varset.payment_method),
        payout_method => V#payproc_Varset.payout_method,
        wallet_id => V#payproc_Varset.wallet_id,
        p2p_tool => V#payproc_Varset.p2p_tool
    }).

prepare_payment_tool_var(PaymentMethodRef) when PaymentMethodRef /= undefined ->
    pm_payment_tool:create_from_method(PaymentMethodRef);
prepare_payment_tool_var(undefined) ->
    undefined.

get_identification_level(#domain_Contract{contractor_id = undefined, contractor = Contractor}, _) ->
    %% TODO legacy, remove after migration
    case Contractor of
        {legal_entity, _} ->
            full;
        _ ->
            none
    end;
get_identification_level(#domain_Contract{contractor_id = ContractorID}, Party) ->
    Contractor = pm_party:get_contractor(ContractorID, Party),
    Contractor#domain_PartyContractor.status.
