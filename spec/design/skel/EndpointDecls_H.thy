(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

header "Function Declarations for Endpoints"

theory EndpointDecls_H
imports FaultMonad_H
begin

#INCLUDE_HASKELL SEL4/Object/Endpoint.lhs decls_only

end
