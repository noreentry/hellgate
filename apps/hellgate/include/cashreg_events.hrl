-ifndef(__hellgate_cashreg_events__).
-define(__hellgate_cashreg_events__, 42).

% Events

-define(cashreg_receipt_created(ReceiptParams, Proxy),
    {receipt_created, #cashreg_proc_ReceiptCreated{
        receipt_params = ReceiptParams,
        proxy = Proxy
    }}
).

-define(cashreg_receipt_registered(ReceiptRegEntry),
    {receipt_registered, #cashreg_proc_ReceiptRegistered{receipt_reg_entry = ReceiptRegEntry}}).

-define(cashreg_receipt_failed(Failure),
    {receipt_failed, #cashreg_proc_ReceiptFailed{failure = Failure}}).

-define(cashreg_receipt_session_changed(Payload),
    {receipt_session_changed, #cashreg_proc_ReceiptSessionChange{
        payload = Payload
    }}
).

%% Sessions

-define(cashreg_receipt_session_started(),
    {session_started,
        #cashreg_proc_SessionStarted{}
    }
).
-define(cashreg_receipt_session_finished(Result),
    {session_finished,
        #cashreg_proc_SessionFinished{result = Result}
    }
).
-define(cashreg_receipt_session_suspended(Tag),
    {session_suspended,
        #cashreg_proc_SessionSuspended{tag = Tag}
    }
).
-define(cashreg_receipt_proxy_st_changed(ProxySt),
    {session_proxy_state_changed,
        #cashreg_proc_SessionProxyStateChanged{proxy_state = ProxySt}
    }
).

-define(cashreg_receipt_session_succeeded(),
    {succeeded, #cashreg_proc_SessionSucceeded{}}
).
-define(cashreg_receipt_session_failed(Failure),
    {failed, #cashreg_proc_SessionFailed{failure = Failure}}
).

-endif.