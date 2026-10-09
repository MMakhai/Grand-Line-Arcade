-- Grand Line Arcade: kalıcı toplam Bounty + ortak leaderboard
-- Supabase Dashboard > SQL Editor içinde dosyanın tamamını bir kez çalıştır.

create table if not exists public.pirate_bounties (
  pirate_name text primary key,
  display_name text,
  avatar_url text,
  total_bounty bigint not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.pirate_bounties
  add column if not exists display_name text,
  add column if not exists avatar_url text,
  add column if not exists total_bounty bigint not null default 0,
  add column if not exists updated_at timestamptz not null default now();

update public.pirate_bounties
set display_name = coalesce(nullif(display_name, ''), pirate_name),
    avatar_url = coalesce(nullif(avatar_url, ''), 'Assets/avatars/onepiece-001.png')
where display_name is null or avatar_url is null;

create unique index if not exists pirate_bounties_pirate_name_uidx on public.pirate_bounties (pirate_name);

alter table public.pirate_bounties enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'pirate_bounties'
      and policyname = 'Bounties can be viewed'
  ) then
    create policy "Bounties can be viewed" on public.pirate_bounties
      for select to anon, authenticated using (true);
  end if;
end $$;

grant select on public.pirate_bounties to anon, authenticated;

-- Eski imzalı RPC varsa kaldır; yeni sürüm görünen isim/avatarı da günceller.
drop function if exists public.add_pirate_bounty(text, bigint);
drop function if exists public.add_pirate_bounty(text, bigint, text, text);

create function public.add_pirate_bounty(
  p_pirate_name text,
  p_amount bigint,
  p_display_name text,
  p_avatar_url text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_name text;
  safe_display_name text;
  safe_avatar text;
  new_total bigint;
begin
  normalized_name := lower(regexp_replace(trim(coalesce(p_pirate_name, '')), '\s+', ' ', 'g'));
  safe_display_name := left(trim(coalesce(p_display_name, p_pirate_name, 'Korsan')), 16);
  safe_avatar := coalesce(p_avatar_url, 'Assets/avatars/onepiece-001.png');

  if normalized_name = '' or length(normalized_name) > 16 then
    raise exception 'Invalid pirate name';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 100000000000 then
    raise exception 'Invalid bounty amount';
  end if;
  if safe_avatar !~ '^Assets/avatars/onepiece-[0-9]{3}\.png$' then
    safe_avatar := 'Assets/avatars/onepiece-001.png';
  end if;

  insert into public.pirate_bounties
    (pirate_name, display_name, avatar_url, total_bounty, updated_at)
  values
    (normalized_name, safe_display_name, safe_avatar, p_amount, now())
  on conflict (pirate_name)
  do update set
    total_bounty = public.pirate_bounties.total_bounty + excluded.total_bounty,
    display_name = excluded.display_name,
    avatar_url = excluded.avatar_url,
    updated_at = now()
  returning total_bounty into new_total;

  return new_total;
end;
$$;

grant execute on function public.add_pirate_bounty(text, bigint, text, text)
  to anon, authenticated;
