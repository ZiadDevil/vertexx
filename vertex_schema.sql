-- Enable necessary extensions
create extension if not exists "uuid-ossp";

-- 1. ENUMS
-- Define roles for RBAC
create type user_role as enum ('super_admin', 'sales', 'team', 'client');
-- Define order status
create type order_status as enum ('pending', 'claimed', 'in_progress', 'review', 'completed', 'cancelled');
-- Define portfolio categories
create type portfolio_category as enum ('web', 'design', 'marketing');

-- 2. PROFILES TABLE (Extends auth.users)
create table public.profiles (
  id uuid references auth.users on delete cascade not null primary key,
  email text unique not null,
  full_name text,
  avatar_url text,
  role user_role default 'client'::user_role,
  xp_points integer default 0,
  referral_code text unique,
  created_at timestamptz default timezone('utc'::text, now()) not null,
  updated_at timestamptz default timezone('utc'::text, now()) not null
);

-- RLS for Profiles
alter table public.profiles enable row level security;

-- Policies
-- Public profiles are viewable by everyone (for now, or restrict to auth agents)
create policy "Public profiles are viewable by everyone." on public.profiles
  for select using (true);

-- Users can insert their own profile (usually handled by trigger, but just in case)
create policy "Users can insert their own profile." on public.profiles
  for insert with check (auth.uid() = id);

-- Users can update own profile
create policy "Users can update own profile." on public.profiles
  for update using (auth.uid() = id);

-- Super Admins can update any profile (e.g. promoting roles)
create policy "Super Admins can update any profile." on public.profiles
  for update using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role = 'super_admin'
    )
  );

-- 3. ORDERS TABLE
create table public.orders (
  id uuid default uuid_generate_v4() primary key,
  client_id uuid references public.profiles(id) not null,
  service_type text not null, -- e.g., 'Web Development', 'SEO Audit'
  description text,
  status order_status default 'pending'::order_status,
  claimed_by uuid references public.profiles(id), -- Staff who claimed the order
  price decimal(10, 2),
  currency text default 'EGP',
  milestones jsonb default '[]'::jsonb, -- Store milestones as JSON array
  created_at timestamptz default timezone('utc'::text, now()) not null,
  updated_at timestamptz default timezone('utc'::text, now()) not null
);

-- RLS for Orders
alter table public.orders enable row level security;

-- Policies for Orders
-- Clients can view their own orders
create policy "Clients can view own orders." on public.orders
  for select using (auth.uid() = client_id);

-- Staff (Super Admin, Sales, Team) can view ALL orders
create policy "Staff can view all orders." on public.orders
  for select using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role in ('super_admin', 'sales', 'team')
    )
  );

-- Clients can create orders
create policy "Clients can create orders." on public.orders
  for insert with check (auth.uid() = client_id);

-- Staff can update orders (claim, change status, etc.)
create policy "Staff can update orders." on public.orders
  for update using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role in ('super_admin', 'sales', 'team')
    )
  );

-- 4. PORTFOLIO TABLE
create table public.portfolio (
  id uuid default uuid_generate_v4() primary key,
  title text not null,
  description text,
  category portfolio_category not null,
  images text[], -- Array of image URLs
  live_url text,
  created_at timestamptz default timezone('utc'::text, now()) not null
);

-- RLS for Portfolio
alter table public.portfolio enable row level security;

-- Policies for Portfolio
-- Everyone can view portfolio items
create policy "Everyone can view portfolio." on public.portfolio
  for select using (true);

-- Only Admins/Staff can insert/update/delete portfolio items
create policy "Staff can manage portfolio." on public.portfolio
  for all using (
    exists (
      select 1 from public.profiles
      where id = auth.uid() and role in ('super_admin', 'sales', 'team')
    )
  );

-- 5. MESSAGES TABLE (Realtime Chat)
create table public.messages (
  id uuid default uuid_generate_v4() primary key,
  order_id uuid references public.orders(id) not null,
  sender_id uuid references public.profiles(id) not null,
  content text not null,
  is_system_message boolean default false,
  created_at timestamptz default timezone('utc'::text, now()) not null
);

-- RLS for Messages
alter table public.messages enable row level security;

-- Policies for Messages
-- Participants (Client or Staff) can view messages for an order
create policy "Participants can view messages." on public.messages
  for select using (
    exists (
      select 1 from public.orders
      where id = messages.order_id
      and (
        client_id = auth.uid() -- Is the client
        or exists ( -- Is staff
          select 1 from public.profiles
          where id = auth.uid() and role in ('super_admin', 'sales', 'team')
        )
      )
    )
  );

-- Participants can send messages
create policy "Participants can send messages." on public.messages
  for insert with check (
    auth.uid() = sender_id
    and exists (
      select 1 from public.orders
      where id = messages.order_id
      and (
        client_id = auth.uid()
        or exists (
          select 1 from public.profiles
          where id = auth.uid() and role in ('super_admin', 'sales', 'team')
        )
      )
    )
  );

-- 6. TRIGGERS & FUNCTIONS

-- Function to handle new user signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (new.id, new.email, new.raw_user_meta_data->>'full_name', 'client');
  -- Optional: Create a 'welcome' notification or message
  return new;
end;
$$ language plpgsql security definer;

-- Trigger to call the function on auth.users insert
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Indexes for performance
create index idx_orders_client on public.orders(client_id);
create index idx_orders_status on public.orders(status);
create index idx_messages_order on public.messages(order_id);
