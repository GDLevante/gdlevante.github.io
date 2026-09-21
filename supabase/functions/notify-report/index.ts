import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
  if (req.method === 'OPTIONS') return new Response('ok',{headers:cors})
  try {
    const {reportId}=await req.json()
    const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    const {data,error}=await admin.from('reports').select('public_code,finding_type,created_at').eq('id',reportId).single()
    if(error) throw error
    const response=await fetch('https://api.resend.com/emails',{
      method:'POST',headers:{Authorization:`Bearer ${Deno.env.get('RESEND_API_KEY')}`,'Content-Type':'application/json'},
      body:JSON.stringify({from:Deno.env.get('MAIL_FROM'),to:['ghostdivinglevante@gmail.com'],subject:`Nuevo aviso ${data.public_code}`,html:`<h2>Nuevo aviso Ghost Diving Levante</h2><p><strong>Código:</strong> ${data.public_code}</p><p><strong>Tipo:</strong> ${data.finding_type}</p><p>Entra en el panel de gestión para revisar coordenadas y adjuntos.</p>`})
    })
    if(!response.ok) throw new Error(await response.text())
    return new Response(JSON.stringify({ok:true}),{headers:{...cors,'Content-Type':'application/json'}})
  } catch(error){return new Response(JSON.stringify({error:String(error)}),{status:400,headers:{...cors,'Content-Type':'application/json'}})}
})
