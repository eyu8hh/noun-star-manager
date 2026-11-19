import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const allowedOrigins = new Set(["https://eyu8hh.github.io","http://localhost:3000","http://127.0.0.1:5500"]);
const json=(body:unknown,status=200,origin="https://eyu8hh.github.io")=>new Response(JSON.stringify(body),{status,headers:{"Access-Control-Allow-Origin":origin,"Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin","Content-Type":"application/json"}});
Deno.serve(async(req:Request)=>{
 const requestedOrigin=req.headers.get("Origin")??"",origin=allowedOrigins.has(requestedOrigin)?requestedOrigin:"https://eyu8hh.github.io";
 if(req.method==="OPTIONS")return new Response("ok",{headers:{"Access-Control-Allow-Origin":origin,"Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"}});
 if(req.method!=="POST")return json({error:"Method not allowed"},405,origin);
 const url=Deno.env.get("SUPABASE_URL"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!url||!serviceKey)return json({error:"Server configuration missing"},500,origin);
 let input:{username?:string;display_name?:string;password?:string};
 try{input=await req.json()}catch{return json({error:"Invalid request"},400,origin)}
 const username=String(input.username??"").trim().toLowerCase(),displayName=String(input.display_name??"").trim(),password=String(input.password??"");
 if(!/^[a-z0-9_]{4,20}$/.test(username))return json({error:"اسم المستخدم يجب أن يكون من 4 إلى 20 حرفاً إنجليزياً أو رقماً أو _"},400,origin);
 if(displayName.length<2||displayName.length>80)return json({error:"يرجى إدخال اسم عرض صحيح"},400,origin);
 if(password.length<10||password.length>72)return json({error:"كلمة المرور يجب أن تكون بين 10 و72 حرفاً"},400,origin);
 const admin=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
 const forwarded=req.headers.get("x-forwarded-for")?.split(",")[0]?.trim()??"unknown";
 const digest=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(forwarded));
 const ipHash=[...new Uint8Array(digest)].map(b=>b.toString(16).padStart(2,"0")).join("");
 const since=new Date(Date.now()-15*60*1000).toISOString();
 const {count,error:countError}=await admin.from("audience_signup_attempts").select("id",{count:"exact",head:true}).eq("ip_hash",ipHash).gte("created_at",since);
 if(countError)return json({error:"تعذر التحقق من طلب التسجيل"},503,origin);
 if((count??0)>=5)return json({error:"محاولات كثيرة. حاول بعد 15 دقيقة."},429,origin);
 const {error:attemptError}=await admin.from("audience_signup_attempts").insert({ip_hash:ipHash});
 if(attemptError)return json({error:"تعذر إكمال التسجيل"},503,origin);
 const email="fan+"+username+"@fans.nounstar.club";
 const {data:created,error:createError}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{display_name:displayName,account_kind:"audience"}});
 if(createError||!created.user){
  const duplicate=/already|exists|registered/i.test(createError?.message??"");
  return json({error:duplicate?"اسم المستخدم مستخدم بالفعل":"تعذر إنشاء الحساب"},duplicate?409:400,origin);
 }
 const userId=created.user.id;
 const {error:profileError}=await admin.from("profiles").update({role:"fan",display_name:displayName}).eq("id",userId);
 const {error:memberError}=await admin.from("audience_members").insert({user_id:userId,username,display_name:displayName,notifications_enabled:true});
 if(profileError||memberError){await admin.auth.admin.deleteUser(userId);return json({error:"تعذر تهيئة حساب الجمهور. حاول مرة أخرى."},500,origin)}
 return json({ok:true,username,role:"fan"},201,origin);
});