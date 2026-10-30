-- Адуучин тэмцээний бүртгэл. Supabase SQL Editor дээр нэг удаа ажиллуулна.
create table if not exists public.registrations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  last_name text not null check (char_length(last_name) between 1 and 60),
  first_name text not null check (char_length(first_name) between 1 and 60),
  school text not null check (char_length(school) between 1 and 120),
  major text check (major is null or char_length(major) <= 120),
  course text not null,
  class_group text not null check (char_length(class_group) between 1 and 40),
  phone text not null unique check (phone ~ '^[0-9]{8,12}$'),
  email text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  trm_awareness smallint not null check (trm_awareness between 1 and 5),      -- 5 = Маш сайн, 1 = Огт мэдэхгүй
  company_awareness smallint not null check (company_awareness between 1 and 5) -- Монгол Экүэстрэн ХХК
);

alter table public.registrations enable row level security;

-- Зочин (anon) зөвхөн бичиж чадна; унших, засах, устгах эрхгүй.
drop policy if exists "anon can insert" on public.registrations;
create policy "anon can insert" on public.registrations
  for insert to anon with check (true);

-- ===== Азтан шалгаруулах =====
create table if not exists public.winners (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null unique references public.registrations(id),
  drawn_at timestamptz not null default now()
);
alter table public.winners enable row level security;   -- policy байхгүй = anon-д хаалттай

create table if not exists public.admin_secret (pass text not null);
alter table public.admin_secret enable row level security;
-- ДООРХ НУУЦ ҮГИЙГ ӨӨРИЙНХӨӨРӨӨ СОЛИНО:
insert into public.admin_secret (pass) select '<set-in-supabase>' where not exists (select 1 from public.admin_secret);

-- Нууц үг зөв бол өмнө нь хожоогүй бүртгэлээс санамсаргүй нэгийг сонгож буцаана.
create or replace function public.draw_winner(p_pass text)
returns table(full_name text, school text, phone text, email text, remaining int)
language plpgsql security definer set search_path = public as $$
declare r public.registrations;
begin
  if not exists (select 1 from admin_secret where pass = p_pass) then
    raise exception 'unauthorized';
  end if;
  select * into r from registrations g
   where not exists (select 1 from winners w where w.registration_id = g.id)
   order by random() limit 1;
  if r.id is null then raise exception 'no_candidates'; end if;
  insert into winners(registration_id) values (r.id);
  return query select r.last_name || ' ' || r.first_name, r.school, r.phone, r.email,
    (select count(*)::int from registrations g where not exists (select 1 from winners w where w.registration_id = g.id));
end $$;

create or replace function public.draw_stats(p_pass text)
returns table(total int, remaining int)
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from admin_secret where pass = p_pass) then raise exception 'unauthorized'; end if;
  return query select (select count(*)::int from registrations),
    (select count(*)::int from registrations g where not exists (select 1 from winners w where w.registration_id = g.id));
end $$;

revoke all on function public.draw_winner(text), public.draw_stats(text) from public;
grant execute on function public.draw_winner(text), public.draw_stats(text) to anon;
