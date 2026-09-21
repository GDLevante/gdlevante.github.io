-- Ejecutar una sola vez en proyectos que ya aplicaron 001_initial.sql.
-- Repara perfiles existentes y endurece los cambios de rol.

create or replace function public.current_role() returns public.user_role
language sql stable security definer set search_path=public as $$
  select role from public.profiles where id=auth.uid() and approved=true
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if not coalesce(new.is_anonymous,false) then
    insert into public.profiles(id,display_name)
    values(new.id,coalesce(new.raw_user_meta_data->>'display_name',new.email,''))
    on conflict(id) do nothing;
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users for each row execute procedure public.handle_new_user();

insert into public.profiles(id,display_name)
select u.id,coalesce(u.raw_user_meta_data->>'display_name',u.email,'')
from auth.users u
where not coalesce(u.is_anonymous,false)
on conflict(id) do nothing;

create or replace function public.protect_profile_privileges() returns trigger
language plpgsql security definer set search_path=public as $$
declare actor_role public.user_role;
begin
  if auth.uid() is null then return new; end if;
  if new.role is distinct from old.role or new.approved is distinct from old.approved then
    select role into actor_role from public.profiles where id=auth.uid() and approved=true;
    if actor_role='superadmin' then return new; end if;
    if actor_role='admin' and old.role='diver' and new.role='diver' then return new; end if;
    raise exception 'Only an authorized administrator may change roles or approval';
  end if;
  return new;
end $$;

drop trigger if exists protect_profile_privileges on public.profiles;
create trigger protect_profile_privileges
before update on public.profiles for each row execute procedure public.protect_profile_privileges();

