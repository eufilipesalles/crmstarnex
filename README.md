# Starnex · Funil Diagnóstico + CRM

- `/` → funil público (quiz, resultado, manual em PDF, pedido do Plano de Recuperação)
- `/crm` → CRM Starnex Lead Flow (login com e-mail e senha do Supabase)
- `supabase/` → scripts do banco (não vão para o ar)

## Situação
- Banco "Starnex lp e CRM": scripts `01` e `02` já aplicados (28/10/2026).
- Chave pública do Supabase já configurada no funil e no CRM.

## Falta
1. Supabase → Authentication → Users: criar o usuário eufilipesalles.contato@gmail.com com senha.
2. Supabase → Authentication → Sign In / Providers: desativar "Allow new users to sign up".
3. Para liberar outra pessoa no CRM: `insert into public.crm_usuarios (email) values ('email@dominio.com');`
