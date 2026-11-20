# NOUN STAR — Web Push setup

The production Web Push system is provisioned in the linked Supabase project.

## Runtime components

- `public.nsm_push_subscriptions`: per-device browser subscriptions. RLS is enabled and only `service_role` has table access.
- `public.nsm_get_push_secrets()`: exposes the three Web Push secrets to `service_role` only.
- `public.nsm_claim_due_push_notifications()`: claims due notifications in small batches with row locking to avoid duplicate sends.
- `nsm-push` Edge Function: authenticates manager actions, saves/removes device subscriptions, sends test notifications, dispatches due notifications, and removes expired endpoints.
- `nsm-push-dispatch-every-minute`: Supabase Cron job that invokes the Edge Function through `pg_net`.

## Vault entries

Never commit these values to GitHub. The live project has the following entries in Supabase Vault:

- `nsm_vapid_public`
- `nsm_vapid_private`
- `nsm_push_cron_token`
- `nsm_project_url`
- `nsm_publishable_key`

The VAPID private key and cron token must remain server-side. The browser receives only the public VAPID key after the authenticated manager check.

## Browser enrollment

1. Sign in using a manager account.
2. Open **مركز الإشعارات**.
3. Select **تفعيل إشعارات الهاتف** and allow the browser permission prompt.
4. Select **إرسال إشعار تجريبي** and confirm the phone receives it.
5. To stop notifications on one device, use **إيقاف هذا الجهاز**.

On iPhone, Web Push requires iOS/iPadOS 16.4 or later and the site must be added to the Home Screen and opened as an installed web app. On Android, use a current Chrome-based browser and allow notifications.

## Delivery behavior

The scheduler runs once per minute. It sends rows in `club_notifications` when `scheduled_for` is null or has arrived, provided the notification has not been dismissed or sent already. Future-dated rows remain queued. Expired push endpoints (HTTP 404/410) are deleted automatically.

The existing in-app notification center remains the source of truth; push is an additional delivery channel. Disabling a device subscription does not delete notification history.
