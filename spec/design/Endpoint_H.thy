(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

header "Endpoints"

theory Endpoint_H
imports
  EndpointDecls_H
  TCB_H
  ThreadDecls_H
  CSpaceDecls_H
  FaultHandlerDecls_H
  AsyncEndpoint_H
begin

defs sendIPC_def:
"sendIPC blocking call badge canGrant thread epptr\<equiv> (do
        ep \<leftarrow> getEndpoint epptr;
        (case ep of 
            IdleEP \<Rightarrow> if blocking then  (do
                setThreadState (BlockedOnSend_ \<lparr>
                    blockingIPCEndpoint= epptr,
                    blockingIPCBadge= badge,
                    blockingIPCCanGrant= canGrant,
                    blockingIPCIsCall= call \<rparr>) thread;
                setEndpoint epptr $ SendEP [thread]
            od)
            else  return ()
            | SendEP queue \<Rightarrow> if blocking then  (do
                setThreadState (BlockedOnSend_ \<lparr>
                    blockingIPCEndpoint= epptr,
                    blockingIPCBadge= badge,
                    blockingIPCCanGrant= canGrant,
                    blockingIPCIsCall= call \<rparr>) thread;
                setEndpoint epptr $ SendEP $ queue @ [thread]
            od)
            else  return ()
            | RecvEP v1 \<Rightarrow> (case v1 of dest # queue \<Rightarrow>  (do
                setEndpoint epptr $ (case queue of
                      [] \<Rightarrow>   IdleEP
                    | _ \<Rightarrow>   RecvEP queue
                    );
                recvState \<leftarrow> getThreadState dest;
                haskell_assert (isReceive recvState)
                       [];
                diminish \<leftarrow> return ( blockingIPCDiminishCaps recvState);
                doIPCTransfer thread (Just epptr) badge canGrant
                    dest diminish;
                setThreadState Running dest;
                attemptSwitchTo dest;
                fault \<leftarrow> threadGet tcbFault thread;
                (case (call, fault, canGrant \<and> Not diminish) of
                      (False, None, _) \<Rightarrow>   return ()
                    | (_, _, True) \<Rightarrow>   setupCallerCap thread dest
                    | _ \<Rightarrow>   setThreadState Inactive thread
                    )
            od)
            | [] \<Rightarrow>  haskell_fail []
            )
            )
od)"

defs receiveIPC_def:
"receiveIPC thread x1\<equiv> (let cap = x1 in
  if isEndpointCap cap
  then   (do
        epptr \<leftarrow> return ( capEPPtr cap);
        ep \<leftarrow> getEndpoint epptr;
        diminish \<leftarrow> return ( Not $ capEPCanSend cap);
        (case ep of
              IdleEP \<Rightarrow>   (do
                setThreadState (BlockedOnReceive_ \<lparr>
                    blockingIPCEndpoint= epptr,
                    blockingIPCDiminishCaps= diminish \<rparr>) thread;
                setEndpoint epptr $ RecvEP [thread]
              od)
            | RecvEP queue \<Rightarrow>   (do
                setThreadState (BlockedOnReceive_ \<lparr>
                    blockingIPCEndpoint= epptr,
                    blockingIPCDiminishCaps= diminish \<rparr>) thread;
                setEndpoint epptr $ RecvEP $ queue @ [thread]
            od)
            | SendEP (sender#queue) \<Rightarrow>   (do
                setEndpoint epptr $ (case queue of
                      [] \<Rightarrow>   IdleEP
                    | _ \<Rightarrow>   SendEP queue
                    );
                senderState \<leftarrow> getThreadState sender;
                haskell_assert (isSend senderState)
                       [];
                badge \<leftarrow> return ( blockingIPCBadge senderState);
                canGrant \<leftarrow> return ( blockingIPCCanGrant senderState);
                doIPCTransfer sender (Just epptr) badge canGrant
                    thread diminish;
                call \<leftarrow> return ( blockingIPCIsCall senderState);
                fault \<leftarrow> threadGet tcbFault sender;
                (case (call, fault, canGrant \<and> Not diminish) of
                      (False, None, _) \<Rightarrow>   (do
                        setThreadState Running sender;
                        switchIfRequiredTo sender
                      od)
                    | (_, _, True) \<Rightarrow>   setupCallerCap sender thread
                    | _ \<Rightarrow>   setThreadState Inactive sender
                    )
            od)
            | SendEP [] \<Rightarrow>   haskell_fail []
            )
  od)
  else   haskell_fail []
  )"

defs replyFromKernel_def:
"replyFromKernel thread x1\<equiv> (case x1 of
    (resultLabel, resultData) \<Rightarrow>    (do
    destIPCBuffer \<leftarrow> lookupIPCBuffer True thread;
    asUser thread $ setRegister badgeRegister 0;
    len \<leftarrow> setMRs thread destIPCBuffer resultData;
    msgInfo \<leftarrow> return ( MI_ \<lparr>
            msgLength= len,
            msgExtraCaps= 0,
            msgCapsUnwrapped= 0,
            msgLabel= resultLabel \<rparr>);
    setMessageInfo thread msgInfo
    od)
  )"

defs ipcCancel_def:
"ipcCancel tptr \<equiv>
        let
            replyIPCCancel = (do
                threadSet (\<lambda> tcb. tcb \<lparr>tcbFault := Nothing\<rparr>) tptr;
                slot \<leftarrow> getThreadReplySlot tptr;
                callerCap \<leftarrow> liftM (mdbNext \<circ> cteMDBNode) $ getCTE slot;
                when (callerCap \<noteq> nullPointer) $ (do
                    stateAssert (capHasProperty callerCap isReplyCap)
                        [];
                    cteDeleteOne callerCap
                od)
            od);
            isIdle = (\<lambda>  ep. (case ep of
                  IdleEP \<Rightarrow>   True
                | _ \<Rightarrow>   False
                ));
            blockedIPCCancel = (\<lambda>  state. (do
                epptr \<leftarrow> return ( blockingIPCEndpoint state);
                ep \<leftarrow> getEndpoint epptr;
                haskell_assert (Not $ isIdle ep)
                    [];
                queue' \<leftarrow> return ( delete tptr $ epQueue ep);
                ep' \<leftarrow> (case queue' of
                      [] \<Rightarrow>   return IdleEP
                    | _ \<Rightarrow>   return $ ep \<lparr> epQueue := queue' \<rparr>
                    );
                setEndpoint epptr ep';
                setThreadState Inactive tptr
            od))
        in
                        (do
        state \<leftarrow> getThreadState tptr;
        (case state of
              BlockedOnSend _ _ _ _ \<Rightarrow>   blockedIPCCancel state
            | BlockedOnReceive _ _ \<Rightarrow>   blockedIPCCancel state
            | BlockedOnAsyncEvent _ \<Rightarrow>   asyncIPCCancel tptr (waitingOnAsyncEP state)
            | BlockedOnReply  \<Rightarrow>   replyIPCCancel
            | _ \<Rightarrow>   return ()
            )
                        od)"

defs epCancelAll_def:
"epCancelAll epptr\<equiv> (do
        ep \<leftarrow> getEndpoint epptr;
        (case ep of
              IdleEP \<Rightarrow>  
                return ()
            | _ \<Rightarrow>   (do
                setEndpoint epptr IdleEP;
                forM_x (epQueue ep) (\<lambda> t. (do
                    setThreadState Restart t;
                    tcbSchedEnqueue t
                od)
                                     );
                rescheduleRequired
            od)
            )
od)"

defs epCancelBadgedSends_def:
"epCancelBadgedSends epptr badge\<equiv> (do
    ep \<leftarrow> getEndpoint epptr;
    (case ep of
          IdleEP \<Rightarrow>   return ()
        | RecvEP _ \<Rightarrow>   return ()
        | SendEP queue \<Rightarrow>   (do
            setEndpoint epptr IdleEP;
            queue' \<leftarrow> (flip filterM queue) (\<lambda> t. (do
                st \<leftarrow> getThreadState t;
                if blockingIPCBadge st = badge
                    then (do
                        setThreadState Restart t;
                        tcbSchedEnqueue t;
                        return False
                    od)
                    else return True
            od));
            ep' \<leftarrow> (case queue' of
                  [] \<Rightarrow>   return IdleEP
                | _ \<Rightarrow>   return $ SendEP_ \<lparr> epQueue= queue' \<rparr>
                );
            setEndpoint epptr ep';
            rescheduleRequired
        od)
        )
od)"

defs getEndpoint_def:
"getEndpoint \<equiv> getObject"

defs setEndpoint_def:
"setEndpoint \<equiv> setObject"


end
