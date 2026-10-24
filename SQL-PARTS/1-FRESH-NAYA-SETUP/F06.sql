-- ============================================================================
-- SUNPOWERS — NAYA PROJECT SETUP — part 6 of 18
-- Naya (khali) Supabase project: pehle F01..F06, phir 2-UPDATE ke U01..U12.
-- Supabase -> SQL Editor: paste the WHOLE part and press Run. Run the parts in order (F01 -> F06, phir U01 -> U12). Safe to re-run.
-- ============================================================================

do $$ begin
  grant execute on function public.crm_login(jsonb), public.crm_logout(jsonb), public.crm_me(jsonb),
    public.crm_password(jsonb), public.crm_users_list(jsonb), public.crm_user_save(jsonb), public.crm_user_delete(jsonb), public.crm_roles_get(jsonb), public.crm_role_save(jsonb),
    public.crm_settings_get(jsonb), public.crm_settings_save(jsonb), public.crm_list(jsonb), public.crm_get(jsonb), public.crm_save(jsonb), public.crm_status(jsonb),
    public.crm_convert(jsonb), public.crm_delete(jsonb), public.crm_assign(jsonb), public.crm_lead_import(jsonb), public.crm_file_put(jsonb), public.crm_file_get(jsonb),
    public.crm_search(jsonb), public.crm_today_list(jsonb), public.crm_team_stats(jsonb), public.crm_dashboard(jsonb), public.crm_pulse(jsonb), public.crm_activity_list(jsonb),
    public.crm_orders(jsonb), public.crm_order_status(jsonb), public.crm_to_store(jsonb), public.crm_consumer_me(jsonb), public.crm_consumer_save(jsonb), public.crm_consumers(jsonb),
    public.crm_auth_mode(jsonb), public.crm_auth_start(jsonb), public.crm_auth_resend(jsonb), public.crm_auth_otp(jsonb), public.crm_auth_master(jsonb), public.crm_auth_pin(jsonb), public.crm_auth_setpin(jsonb),
    public.crm_auth_forgot(jsonb), public.crm_auth_answer(jsonb), public.crm_auth_reset_info(jsonb), public.crm_auth_reset(jsonb), public.crm_auth_register(jsonb),
    public.crm_auth_me(jsonb), public.crm_auth_device_remove(jsonb), public.crm_auth_logout_all(jsonb), public.crm_auth_change_pin(jsonb), public.crm_auth_questions(jsonb),
    public.crm_auth_admin_get(jsonb), public.crm_auth_admin_save(jsonb), public.crm_auth_test_mail(jsonb), public.crm_auth_mail_status(jsonb), public.crm_auth_user_reset(jsonb), public.crm_backup(jsonb), public.crm_auth_mkt_login(jsonb), public.crm_auth_mkt_setq(jsonb), public.crm_auth_mkt_forgot(jsonb), public.crm_auth_mkt_answer(jsonb), public.crm_mkt_user(jsonb), public.crm_mkt_get(jsonb), public.crm_mkt_save(jsonb), public.crm_mkt_stats(jsonb), public.sp_admin_crm_items(text), public.sp_admin_crm_item_set(text, bigint, text, text, text)
  to anon, authenticated;
exception when undefined_object then null; end $$;

notify pgrst, 'reload schema';
select 'Sunpowers CRM setup complete ✔' as status;
