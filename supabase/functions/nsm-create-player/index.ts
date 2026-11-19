import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
Deno.serve(async (req: Request) => {
 if (req.method === "OPTIONS") return new Response("ok");
 const url=Deno.env.get("SUPABASE_URL")!, anon=Deno.env.get("SUPABASE_ANON_KEY")!, key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
 const token=(req.headers.get("Authorization")??"").replace(/^Bearer\s+/i,"");
 const caller=createClient(url,anon,{global:{headers:{Authorization:"Bearer "+token}},auth:{persistSession:false,autoRefreshToken:false}});
 const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data}=await caller.auth.getUser(token); if(!data.user)return new Response("Unauthorized",{status:401});
 const {data:profile}=await admin.from("profiles").select("role").eq("id",data.user.id).maybeSingle();
 if(profile?.role!=="manager")return new Response("Forbidden",{status:403});
 const body=await req.json(); const playerId=String(body.player_id??""); const code=String(body.player_code??"").trim().toUpperCase().replace(/^P-/,""); const password=String(body.password??"");
 if(!playerId||!/^[A-Z0-9_-]{4,20}$/.test(code)||password.length<10)return new Response("Invalid input",{status:400});
 const {data:player}=await admin.from("players").select("id,owner_id,user_id,full_name").eq("id",playerId).eq("owner_id",data.user.id).maybeSingle();
 if(!player)return new Response("Player not found",{status:404});
 if(player.user_id)return new Response("Player already has an account",{status:409});
 const {data:dupe}=await admin.from("players").select("id").ilike("login_code",code).maybeSingle();
 if(dupe)return new Response("Identifier used",{status:409});
 const email="player+"+code.toLowerCase()+"@login.nounstar.club";
 const {data:user,error}=await admin.auth.admin.createUser({email,password,email_confirm:true});
 if(error||!user.user)return new Response("Account creation failed",{status:400});
 const {error:profileError}=await admin.from("profiles").update({display_name:player.full_name,role:"player",club_owner_id:data.user.id}).eq("id",user.user.id);
 if(profileError){await admin.auth.admin.deleteUser(user.user.id);return new Response("Profile save failed",{status:500});}
 const {error:playerError}=await admin.from("players").update({user_id:user.user.id,login_code:code}).eq("id",playerId).eq("owner_id",data.user.id);
 if(playerError){await admin.auth.admin.deleteUser(user.user.id);return new Response("Player link failed",{status:500});}
 return new Response(JSON.stringify({id:user.user.id,player_code:"P-"+code,player_name:player.full_name}),{status:201,headers:{"Content-Type":"application/json"}});
});