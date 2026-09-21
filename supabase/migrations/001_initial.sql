-- Ghost Diving Levante · esquema inicial
create extension if not exists pgcrypto;

create type public.user_role as enum ('diver','admin','superadmin');
create type public.report_status as enum ('pending_review','needs_info','validated','converted','discarded');
create type public.point_status as enum ('reported','pending_inspection','inspected','confirmed','extraction_scheduled','removed','clean','discarded');
create type public.point_visibility as enum ('private','divers','public');
create type public.media_kind as enum ('photo','video');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  phone text,
  usual_area text,
  specialty text,
  role public.user_role not null default 'diver',
  approved boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  public_code text unique not null default ('GDLEV-R-' || extract(year from now())::int || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,6))),
  latitude numeric(9,6) not null check (latitude between -90 and 90),
  longitude numeric(9,6) not null check (longitude between -180 and 180),
  finding_type text not null,
  found_at date,
  depth_m numeric(6,1) check (depth_m between 0 and 300),
  dimensions text,
  description text not null check (char_length(description) between 10 and 3000),
  reporter_name text,
  reporter_email text,
  reporter_phone text,
  status public.report_status not null default 'pending_review',
  privacy_accepted_at timestamptz not null,
  media_consent_at timestamptz not null,
  source_ip_hash text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.points (
  id uuid primary key default gen_random_uuid(),
  public_code text unique not null default ('GDLEV-' || extract(year from now())::int || '-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,6))),
  source_report_id uuid references public.reports(id),
  latitude numeric(9,6) not null,
  longitude numeric(9,6) not null,
  public_latitude numeric(9,6),
  public_longitude numeric(9,6),
  finding_type text not null,
  depth_m numeric(6,1),
  status public.point_status not null default 'reported',
  visibility public.point_visibility not null default 'private',
  public_notes text,
  internal_notes text,
  priority smallint not null default 3 check (priority between 1 and 5),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.report_media (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.reports(id) on delete cascade,
  storage_path text not null unique,
  media_type public.media_kind not null,
  mime_type text not null,
  size_bytes bigint not null,
  publication_approved boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.point_media (
  id uuid primary key default gen_random_uuid(),
  point_id uuid not null references public.points(id) on delete cascade,
  storage_path text not null unique,
  media_type public.media_kind not null,
  phase text not null default 'inspection' check (phase in ('report','inspection','extraction','after')),
  publication_approved boolean not null default false,
  uploaded_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.point_access (
  point_id uuid references public.points(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  primary key(point_id,user_id)
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  entity_type text not null,
  entity_id uuid,
  action text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.current_role() returns public.user_role language sql stable security definer set search_path=public as $$
  select role from public.profiles where id=auth.uid() and approved=true
$$;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,display_name) values(new.id,coalesce(new.raw_user_meta_data->>'display_name',''));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- Entrada pública controlada: devuelve solo identificador y código, nunca el reporte completo.
create or replace function public.submit_report(
  p_latitude numeric, p_longitude numeric, p_finding_type text, p_found_at date,
  p_depth_m numeric, p_dimensions text, p_description text,
  p_reporter_name text, p_reporter_email text
) returns table(id uuid, public_code text)
language plpgsql security definer set search_path=public as $$
begin
  return query
  insert into public.reports(latitude,longitude,finding_type,found_at,depth_m,dimensions,description,reporter_name,reporter_email,privacy_accepted_at,media_consent_at)
  values(p_latitude,p_longitude,p_finding_type,p_found_at,p_depth_m,p_dimensions,p_description,nullif(p_reporter_name,''),nullif(p_reporter_email,''),now(),now())
  returning reports.id,reports.public_code;
end $$;
grant execute on function public.submit_report(numeric,numeric,text,date,numeric,text,text,text,text) to anon,authenticated;

alter table public.profiles enable row level security;
alter table public.reports enable row level security;
alter table public.points enable row level security;
alter table public.report_media enable row level security;
alter table public.point_media enable row level security;
alter table public.point_access enable row level security;
alter table public.audit_log enable row level security;

create policy "own profile or admins read" on public.profiles for select using (id=auth.uid() or public.current_role() in ('admin','superadmin'));
create policy "own profile update" on public.profiles for update using (id=auth.uid()) with check (id=auth.uid());
create policy "admins manage profiles" on public.profiles for all using (public.current_role() in ('admin','superadmin')) with check (public.current_role() in ('admin','superadmin'));

create policy "admins read reports" on public.reports for select to authenticated using (public.current_role() in ('admin','superadmin'));
create policy "admins update reports" on public.reports for update to authenticated using (public.current_role() in ('admin','superadmin'));

create policy "public sees public points" on public.points for select using (visibility='public' or (auth.uid() is not null and public.current_role() is not null and (visibility='divers' or exists(select 1 from public.point_access a where a.point_id=id and a.user_id=auth.uid()))) or public.current_role() in ('admin','superadmin'));
create policy "admins manage points" on public.points for all to authenticated using (public.current_role() in ('admin','superadmin')) with check (public.current_role() in ('admin','superadmin'));

create policy "admins read report media" on public.report_media for select to authenticated using (public.current_role() in ('admin','superadmin'));
create policy "anonymous media rows" on public.report_media for insert to anon,authenticated with check (true);
create policy "team reads allowed point media" on public.point_media for select to authenticated using (public.current_role() is not null and exists(select 1 from public.points p where p.id=point_id));
create policy "team adds point media" on public.point_media for insert to authenticated with check (public.current_role() is not null and uploaded_by=auth.uid());
create policy "admins manage point media" on public.point_media for all to authenticated using (public.current_role() in ('admin','superadmin'));
create policy "admins manage access" on public.point_access for all to authenticated using (public.current_role() in ('admin','superadmin'));
create policy "admins read audit" on public.audit_log for select to authenticated using (public.current_role() in ('admin','superadmin'));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('report-media','report-media',false,104857600,array['image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime']),
 ('point-media','point-media',false,104857600,array['image/jpeg','image/png','image/webp','video/mp4','video/webm','video/quicktime'])
on conflict(id) do nothing;

create policy "public upload report media" on storage.objects for insert to anon,authenticated with check (bucket_id='report-media');
create policy "admins view report files" on storage.objects for select to authenticated using (bucket_id='report-media' and public.current_role() in ('admin','superadmin'));
create policy "team uploads point files" on storage.objects for insert to authenticated with check (bucket_id='point-media' and public.current_role() is not null);
create policy "team views point files" on storage.objects for select to authenticated using (bucket_id='point-media' and public.current_role() is not null);
create policy "admins manage all files" on storage.objects for all to authenticated using (public.current_role() in ('admin','superadmin'));

-- Vista pública: nunca expone datos de contacto, notas internas ni coordenadas exactas.
create view public.public_points with (security_invoker=true) as
select id,public_code,coalesce(public_latitude,round(latitude,3)) as latitude,
       coalesce(public_longitude,round(longitude,3)) as longitude,
       finding_type,depth_m,status,public_notes,created_at
from public.points where visibility='public';
