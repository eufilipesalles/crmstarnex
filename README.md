# Starnex · Funil Diagnóstico + CRM

- `/` → funil público (quiz, resultado, manual em PDF, pedido do Plano de Recuperação)
- `/crm` → CRM Starnex Lead Flow (login com e-mail e senha do Supabase)
- `supabase/` → scripts do banco (não vão para o ar)

## Configuração
1. Rode `supabase/01_funil_diagnostico.sql` no SQL Editor do projeto "Starnex lp e CRM".
2. Coloque seu e-mail em `supabase/02_acesso_crm_vercel.sql` e rode o arquivo.
3. Em Authentication → Users, crie o usuário com esse e-mail. Em Authentication → Sign In / Providers, desative o cadastro público (Allow new users to sign up).
4. Cole a chave publishable do projeto em `index.html` (`supabaseAnonKey`) e em `crm/index.html` (`SUPABASE_KEY`).
