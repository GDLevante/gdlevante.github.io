import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const allowedOrigin = Deno.env.get('ALLOWED_ORIGIN') || 'https://gdlevante.github.io'
  const origin = req.headers.get('origin') || ''
  const cors = {'Access-Control-Allow-Origin': origin === allowedOrigin ? origin : allowedOrigin,'Vary':'Origin','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
  if (req.method === 'OPTIONS') return new Response('ok',{headers:cors})
  try {
    if (origin && origin !== allowedOrigin) return new Response(JSON.stringify({error:'Origen no permitido'}),{status:403,headers:{...cors,'Content-Type':'application/json'}})
    const {reportId}=await req.json()
    if (!reportId || typeof reportId !== 'string') throw new Error('Identificador no válido')
    const authorization=req.headers.get('Authorization') || ''
    const userClient=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:authorization}}})
    const {data:{user},error:userError}=await userClient.auth.getUser()
    if(userError || !user) return new Response(JSON.stringify({error:'No autorizado'}),{status:401,headers:{...cors,'Content-Type':'application/json'}})
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const {data,error}=await admin.from('reports').select('public_code,finding_type,created_at,submitter_user_id,notification_sent_at').eq('id',reportId).single()
    if(error) throw error
    if(data.submitter_user_id !== user.id) return new Response(JSON.stringify({error:'No autorizado'}),{status:403,headers:{...cors,'Content-Type':'application/json'}})
    if(data.notification_sent_at) return new Response(JSON.stringify({ok:true,alreadySent:true}),{headers:{...cors,'Content-Type':'application/json'}})
    const response=await fetch('https://api.resend.com/emails',{
      method:'POST',headers:{Authorization:`Bearer ${Deno.env.get('RESEND_API_KEY')}`,'Content-Type':'application/json'},
      body:JSON.stringify({from:Deno.env.get('MAIL_FROM') || 'Ghost Diving Levante <onboarding@resend.dev>',to:[Deno.env.get('MAIL_TO') || 'ghostdivinglevante@gmail.com'],subject:`Nuevo aviso ${data.public_code}`,html:`<h2>Nuevo aviso Ghost Diving Levante</h2><p><strong>Código:</strong> ${data.public_code}</p><p><strong>Tipo:</strong> ${data.finding_type}</p><p>Entra en el panel de gestión para revisar coordenadas y adjuntos.</p>`})
    })
    if(!response.ok) throw new Error(await response.text())
    await admin.from('reports').update({notification_sent_at:new Date().toISOString()}).eq('id',reportId)
    return new Response(JSON.stringify({ok:true}),{headers:{...cors,'Content-Type':'application/json'}})
  } catch(error){return new Response(JSON.stringify({error:String(error)}),{status:400,headers:{...cors,'Content-Type':'application/json'}})}
})
