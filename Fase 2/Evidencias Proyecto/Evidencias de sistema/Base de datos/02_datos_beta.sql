-- CoreStream: datos beta (sin hashes de contraseña, tokens ni dispositivos)
SET session_replication_role = replica;

--
-- PostgreSQL database dump
--

\restrict 3hcNgBUeGzhr0KggkIg8n9H9rxdGWPbChgwdNzFWu5RDs5Qpg7OGEPLfk0Tb8Er

-- Dumped from database version 15.19 (Debian 15.19-1.pgdg13+2)
-- Dumped by pg_dump version 15.19 (Debian 15.19-1.pgdg13+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Data for Name: alembic_version; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.alembic_version (version_num) FROM stdin;
k7l8m9n0o1p2
\.


--
-- Data for Name: applications; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.applications (name, description, color, icon, is_active, owner_id, id, created_at, updated_at) FROM stdin;
Portal Clientes	\N	#4C8DFF	PC	t	7f003437-a260-4abb-8620-c5ea3dcbf81e	6e1bdfd2-cfd2-580a-9928-58d296ee3fd5	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
API Pagos	\N	#2FBF71	AP	t	7f003437-a260-4abb-8620-c5ea3dcbf81e	8a55b4fa-1a94-5c4c-a7f0-40e8eccbc553	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
App Logística	\N	#8B7CF6	AL	t	7f003437-a260-4abb-8620-c5ea3dcbf81e	3da3c80b-be02-5abb-8906-a8a5a5444273	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
\.


--
-- Data for Name: teams; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.teams (id, created_at, updated_at, name, description) FROM stdin;
\.


--
-- Data for Name: epics; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.epics (title, description, order_index, due_date, is_collapsed, application_id, id, created_at, updated_at, team_id) FROM stdin;
Autenticación y seguridad	\N	0	\N	f	6e1bdfd2-cfd2-580a-9928-58d296ee3fd5	217379c5-54fd-5130-99ba-5555da106f7b	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N
Panel de autogestión	\N	1	\N	f	6e1bdfd2-cfd2-580a-9928-58d296ee3fd5	6db5ebd7-2223-5a94-ad72-7699a1fdc7fb	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N
Conciliación bancaria	\N	0	\N	f	8a55b4fa-1a94-5c4c-a7f0-40e8eccbc553	4d4f738b-2fed-569c-b458-f96b292d55d2	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N
Webhooks de pago	\N	1	\N	f	8a55b4fa-1a94-5c4c-a7f0-40e8eccbc553	4f6f4497-decd-592a-8c1b-566399b1e144	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N
Seguimiento de flotas	\N	0	\N	f	3da3c80b-be02-5abb-8906-a8a5a5444273	b9152905-944f-5e9d-ad45-bc480f2025f6	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N
\.


--
-- Data for Name: tickets; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.tickets (title, description, status, priority, order_index, due_date, pr_link, time_spent_seconds, blocked_time_seconds, epic_id, assignee_id, created_by_id, id, created_at, updated_at, block_reason, estimated_time_seconds, completed_at, blocked_question, blocked_at, timer_started_at, ticket_type, stack_trace, reproduction_steps, browser, operating_system, severity, linked_ticket_id) FROM stdin;
Implementar login con doble factor (TOTP)	Añadir verificación TOTP tras la contraseña. Incluir códigos de respaldo y flujo de recuperación. Criterio de aceptación: compatible con Google Authenticator y 1Password.	IN_PROGRESS	HIGH	0	2026-11-06 17:23:28.440716+00	\N	16440	2100	217379c5-54fd-5130-99ba-5555da106f7b	55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	d04f9d09-e13f-51b1-885e-25836d43d4da	ff906dcc-6ce8-5aae-996b-9be85bcc34c8	2026-10-31 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N	0	\N	\N	\N	\N	DEVELOPMENT	\N	\N	\N	\N	\N	\N
Bloqueo de cuenta tras 5 intentos fallidos	Política de bloqueo temporal (15 min) con aviso por correo al usuario.	BLOCKED_QUESTION	MEDIUM	1	2026-11-05 17:23:28.440716+00	\N	7800	10800	217379c5-54fd-5130-99ba-5555da106f7b	3c212ba7-952f-5b91-8c3b-8d1247f2f8f0	d04f9d09-e13f-51b1-885e-25836d43d4da	e1b10ae9-d149-5156-98b5-4f12eee6876b	2026-10-29 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	¿El bloqueo aplica también a los accesos por API o solo al portal web?	0	\N	\N	2026-11-04 12:23:28.440716+00	\N	DEVELOPMENT	\N	\N	\N	\N	\N	\N
Descarga de facturas en PDF desde el panel	El cliente debe poder descargar sus últimas 24 facturas en PDF con firma digital.	TODO	MEDIUM	0	2026-11-10 17:23:28.440716+00	\N	0	0	6db5ebd7-2223-5a94-ad72-7699a1fdc7fb	\N	7f003437-a260-4abb-8620-c5ea3dcbf81e	aff76bb6-eed7-5d32-9688-96a399c251b0	2026-11-02 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N	0	\N	\N	\N	\N	DEVELOPMENT	\N	\N	\N	\N	\N	\N
Editar datos fiscales con validación de NIF/CIF	Formulario de datos fiscales con validación en tiempo real y verificación contra el censo.	COMPLETED	LOW	1	2026-11-03 17:23:28.440716+00	https://github.com/wellq/portal/pull/412	24300	0	6db5ebd7-2223-5a94-ad72-7699a1fdc7fb	328890cb-25e5-5e9e-95f9-3a21950e4fe3	d04f9d09-e13f-51b1-885e-25836d43d4da	cd40491d-432e-5a50-80b7-f5df98cf28c8	2026-10-26 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N	0	2026-11-03 17:23:28.440716+00	\N	\N	\N	DEVELOPMENT	\N	\N	\N	\N	\N	\N
Matching automático de transferencias SEPA	Cruce automático de transferencias entrantes contra facturas pendientes usando referencia estructurada. Tolerancia de ±0,01 €.	IN_PROGRESS	URGENT	0	2026-11-03 17:23:28.440716+00	\N	33120	3300	4d4f738b-2fed-569c-b458-f96b292d55d2	3c212ba7-952f-5b91-8c3b-8d1247f2f8f0	d04f9d09-e13f-51b1-885e-25836d43d4da	65d01ddf-a052-525f-ad20-7c4f97d47674	2026-10-27 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N	0	\N	\N	\N	\N	DEVELOPMENT	\N	\N	\N	\N	\N	\N
Alertas de descuadre superior a 50 €	Notificar al equipo de finanzas cuando el descuadre diario supere el umbral configurable.	TODO	HIGH	1	2026-11-08 17:23:28.440716+00	\N	0	0	4d4f738b-2fed-569c-b458-f96b292d55d2	55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	7f003437-a260-4abb-8620-c5ea3dcbf81e	a3d48f46-01d8-5bdb-84dd-f964edda97c6	2026-11-01 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N	0	\N	\N	\N	\N	DEVELOPMENT	\N	\N	\N	\N	\N	\N
Reintentos exponenciales en webhooks fallidos	Hasta 6 reintentos con backoff exponencial y firma HMAC en cada entrega.	TODO	HIGH	0	2026-11-07 17:23:28.440716+00	\N	5400	0	4f6f4497-decd-592a-8c1b-566399b1e144	55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	d04f9d09-e13f-51b1-885e-25836d43d4da	c3cf3314-78fe-559c-9873-95b06ff46b30	2026-10-28 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N	0	\N	\N	\N	\N	DEVELOPMENT	\N	\N	\N	\N	\N	\N
Mapa en vivo con posiciones GPS cada 30 s	Websocket con posiciones de la flota y clustering de marcadores en el mapa.	IN_PROGRESS	MEDIUM	0	2026-11-13 17:23:28.440716+00	\N	11100	0	b9152905-944f-5e9d-ad45-bc480f2025f6	328890cb-25e5-5e9e-95f9-3a21950e4fe3	7f003437-a260-4abb-8620-c5ea3dcbf81e	b7926d68-59ec-59a6-95e8-7f3a5b66eff0	2026-10-30 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N	0	\N	\N	\N	\N	DEVELOPMENT	\N	\N	\N	\N	\N	\N
Firma digital de albaranes en la entrega	Captura de firma táctil y foto del paquete como prueba de entrega.	TODO	LOW	1	2026-11-18 17:23:28.440716+00	\N	0	0	b9152905-944f-5e9d-ad45-bc480f2025f6	\N	7f003437-a260-4abb-8620-c5ea3dcbf81e	390c52e3-ade0-5c10-be70-21c49abd1a3f	2026-11-03 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N	0	\N	\N	\N	\N	DEVELOPMENT	\N	\N	\N	\N	\N	\N
PRUEBA01	\N	TODO	MEDIUM	0	\N	\N	0	0	217379c5-54fd-5130-99ba-5555da106f7b	55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	7f003437-a260-4abb-8620-c5ea3dcbf81e	ccbe5567-8f20-4c58-b6cd-65debd7a988b	2026-11-06 01:51:15.5684+00	2026-11-06 01:51:15.5684+00	\N	0	\N	\N	\N	\N	DEVELOPMENT	\N	\N	\N	\N	\N	\N
\.


--
-- Data for Name: documents; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.documents (filename, file_path, file_size, mime_type, doc_type, epic_id, ticket_id, uploaded_by_id, id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: incidents; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.incidents (title, description, status, severity, affected_environment, estimated_resolution_time_seconds, mitigation_state, application_id, created_by_id, assigned_to_id, id, created_at, updated_at) FROM stdin;
Timeout al conciliar extractos de más de 5 000 líneas	El proceso de conciliación supera los 30 s y el worker corta la tarea. Ocurre con los extractos de fin de mes de dos clientes grandes.\n\nContexto importado de la beta:\nReferencia original: INC-57\nCategoría original: CRITICAL_ERROR\nEstado original: IN_PROGRESS\nSeveridad original: CRITICAL\nComentario histórico de Sofía Márquez (2026-11-03T21:23:28.440716+00:00): Reproducido con el extracto de 8 200 líneas. El cuello está en el parser, no en la BD.	INVESTIGATING	P1	DEV	0	\N	8a55b4fa-1a94-5c4c-a7f0-40e8eccbc553	d04f9d09-e13f-51b1-885e-25836d43d4da	3c212ba7-952f-5b91-8c3b-8d1247f2f8f0	21cb4fcc-1ed5-59e7-ac36-eb8483634e23	2026-11-03 15:23:28.440716+00	2026-11-04 17:23:28.440716+00
El selector de idioma no persiste tras cerrar sesión	Al volver a entrar, el portal vuelve a español aunque el usuario eligió inglés.\n\nContexto importado de la beta:\nReferencia original: INC-58\nCategoría original: NON_CRITICAL_ERROR\nEstado original: OPEN\nSeveridad original: LOW	REPORTED	P3	DEV	0	\N	6e1bdfd2-cfd2-580a-9928-58d296ee3fd5	55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	\N	a21e6d6b-7588-5f68-9269-4d237e4c4ecc	2026-11-04 09:23:28.440716+00	2026-11-04 17:23:28.440716+00
Añadir exportación de movimientos a Excel	Varios clientes piden exportar el histórico de movimientos a XLSX además del CSV actual.\n\nContexto importado de la beta:\nReferencia original: INC-55\nCategoría original: NEW_FEATURE\nEstado original: UNDER_REVIEW\nSeveridad original: MEDIUM	REPORTED	P3	DEV	0	\N	6e1bdfd2-cfd2-580a-9928-58d296ee3fd5	7f003437-a260-4abb-8620-c5ea3dcbf81e	55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	515970ef-e17b-5f66-9ad3-135d32808738	2026-11-01 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Contraste insuficiente en el mapa nocturno	Los marcadores grises apenas se distinguen sobre el tema oscuro del mapa.\n\nContexto importado de la beta:\nReferencia original: INC-52\nCategoría original: USABILITY_ISSUE\nEstado original: RESOLVED\nSeveridad original: MEDIUM	RESOLVED	P3	DEV	0	\N	3da3c80b-be02-5abb-8906-a8a5a5444273	328890cb-25e5-5e9e-95f9-3a21950e4fe3	328890cb-25e5-5e9e-95f9-3a21950e4fe3	eda695f0-a0c5-53df-80c1-e0a853f6dcb2	2026-10-29 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Webhook duplicado cuando el receptor responde 5xx lento	Si el receptor tarda >10 s y devuelve 502, el evento se entrega dos veces.\n\nContexto importado de la beta:\nReferencia original: INC-60\nCategoría original: CRITICAL_ERROR\nEstado original: OPEN\nSeveridad original: HIGH	REPORTED	P2	DEV	0	\N	8a55b4fa-1a94-5c4c-a7f0-40e8eccbc553	3c212ba7-952f-5b91-8c3b-8d1247f2f8f0	55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	e9f69c09-8887-5fd5-82ce-f16bbfa0c579	2026-11-04 14:23:28.440716+00	2026-11-06 00:44:19.568091+00
\.


--
-- Data for Name: meetings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.meetings (title, meeting_type, scheduled_at, summary_markdown, application_id, created_by_id, id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: meeting_attendances; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.meeting_attendances (meeting_id, user_id, status, notes, id, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notifications (user_id, ticket_id, title, message, type, is_read, id, created_at, updated_at, read_at) FROM stdin;
55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	a3d48f46-01d8-5bdb-84dd-f964edda97c6	Asignación de ticket	Ana Torres te asignó: “Alertas de descuadre superior a 50 €”	TICKET_ASSIGNED	t	6440c56d-add6-549b-8004-a071a107bfc5	2026-11-01 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N
7f003437-a260-4abb-8620-c5ea3dcbf81e	e1b10ae9-d149-5156-98b5-4f12eee6876b	Pregunta pendiente	Sofía Márquez planteó una pregunta en Portal Clientes: “Bloqueo de cuenta tras 5 intentos fallidos”	QUESTION_RAISED	f	95221e3f-6ca4-5bd9-be9d-1319948ba341	2026-11-04 12:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N
d04f9d09-e13f-51b1-885e-25836d43d4da	e1b10ae9-d149-5156-98b5-4f12eee6876b	Pregunta pendiente	Sofía Márquez planteó una pregunta en Portal Clientes: “Bloqueo de cuenta tras 5 intentos fallidos”	QUESTION_RAISED	f	24f4ba8d-681f-54ce-8f88-fd2179841655	2026-11-04 12:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N
d04f9d09-e13f-51b1-885e-25836d43d4da	\N	Incidencia reportada	Sofía Márquez reportó una incidencia en API Pagos: “Webhook duplicado cuando el receptor responde 5xx lento”	SYSTEM	f	b8389749-64e7-5475-8ea7-c57bac8f516a	2026-11-04 14:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N
7f003437-a260-4abb-8620-c5ea3dcbf81e	cd40491d-432e-5a50-80b7-f5df98cf28c8	Ticket completado	Marco Ibáñez completó un ticket en Portal Clientes: “Editar datos fiscales con validación de NIF/CIF”	TICKET_COMPLETED	t	6960d367-e1ee-58dd-b15a-b1344faa9791	2026-11-03 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N
d04f9d09-e13f-51b1-885e-25836d43d4da	cd40491d-432e-5a50-80b7-f5df98cf28c8	Ticket completado	Marco Ibáñez completó un ticket en Portal Clientes: “Editar datos fiscales con validación de NIF/CIF”	TICKET_COMPLETED	t	fd927517-be49-5343-b037-358aa7081aa9	2026-11-03 17:23:28.440716+00	2026-11-04 17:23:28.440716+00	\N
7f003437-a260-4abb-8620-c5ea3dcbf81e	\N	Incidencia reportada	Sofía Márquez reportó una incidencia en API Pagos: “Webhook duplicado cuando el receptor responde 5xx lento”	SYSTEM	t	ef7ab5ed-940b-5358-a660-9c720cfb89a4	2026-11-04 14:23:28.440716+00	2026-11-05 20:23:06.196338+00	2026-11-05 20:23:06.203087+00
55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	c3cf3314-78fe-559c-9873-95b06ff46b30	Ticket redirigido	Marco Ibáñez te asignó: “Reintentos exponenciales en webhooks fallidos”	TICKET_REDIRECTED	t	093caf00-823c-5975-8a8a-e85ea101506b	2026-11-02 17:23:28.440716+00	2026-11-06 01:51:34.619349+00	2026-11-06 01:51:34.653287+00
55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	ccbe5567-8f20-4c58-b6cd-65debd7a988b	Ticket asignado	Ana Torres te asignó el ticket "PRUEBA01"	TICKET_ASSIGNED	t	65b493ea-3608-4f5d-b55e-8ce4bc1d63cf	2026-11-06 01:51:15.5684+00	2026-11-06 01:51:34.619349+00	2026-11-06 01:51:34.653326+00
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.roles (name, description, id, created_at, updated_at) FROM stdin;
ADMIN	Administrador con acceso total al sistema	80f15027-474b-4a48-8faf-32bff91d39ce	2026-10-31 19:58:00.435774+00	2026-10-31 19:58:00.435774+00
TEAM_LEADER	Líder de equipo con permisos expandidos	3e03ec0d-b7f5-4eb0-a6d7-f00467c4649e	2026-10-31 19:58:00.435774+00	2026-10-31 19:58:00.435774+00
DEVELOPER	Desarrollador regular	79b00b63-c6aa-4cfd-989f-fe23bafd57d5	2026-10-31 19:58:00.435774+00	2026-10-31 19:58:00.435774+00
\.


--
-- Data for Name: subtasks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.subtasks (title, is_completed, order_index, completed_at, ticket_id, id, created_at, updated_at) FROM stdin;
Pantalla de enrolamiento TOTP	t	0	\N	ff906dcc-6ce8-5aae-996b-9be85bcc34c8	4ba51df5-a8bb-5960-ad9c-2e5f7000b73f	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Validación de código de 6 dígitos	t	1	\N	ff906dcc-6ce8-5aae-996b-9be85bcc34c8	1f32b27d-cae6-56b2-a0d0-c8e938ead90c	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Códigos de respaldo descargables	f	2	\N	ff906dcc-6ce8-5aae-996b-9be85bcc34c8	46b902db-be1b-57a3-8fbb-cc10a967fdeb	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Tests E2E del flujo completo	f	3	\N	ff906dcc-6ce8-5aae-996b-9be85bcc34c8	07d95484-cb5e-5363-9ef4-4a4d47b090a7	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Contador de intentos en Redis	t	0	\N	e1b10ae9-d149-5156-98b5-4f12eee6876b	a3db312b-5f84-554a-9886-f01ba931ae37	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Plantilla de correo de aviso	f	1	\N	e1b10ae9-d149-5156-98b5-4f12eee6876b	29da83a1-dd8d-5ebd-88d9-ab0f5e5a975d	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Endpoint GET /invoices/:id/pdf	f	0	\N	aff76bb6-eed7-5d32-9688-96a399c251b0	017131ff-c572-5fdc-b113-05e1adb432f2	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Listado con paginación	f	1	\N	aff76bb6-eed7-5d32-9688-96a399c251b0	565b72f6-1930-5325-89f0-b61324222a57	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Validador NIF/CIF	t	0	\N	cd40491d-432e-5a50-80b7-f5df98cf28c8	dff698fe-e8d1-55f6-b82a-e95892ce6677	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Mensajes de error accesibles	t	1	\N	cd40491d-432e-5a50-80b7-f5df98cf28c8	688d9ceb-b37e-58f8-8b78-f9128c8875c2	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Parser de extractos CAMT.053	t	0	\N	65d01ddf-a052-525f-ad20-7c4f97d47674	1e58293b-59ab-52f1-92aa-26a09ae741e3	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Motor de matching por referencia	t	1	\N	65d01ddf-a052-525f-ad20-7c4f97d47674	690cd896-16fa-579d-86df-46fcdb843de6	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Cola de revisión manual	f	2	\N	65d01ddf-a052-525f-ad20-7c4f97d47674	cae91119-0814-5668-9dd5-01a805e8b08c	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Informe diario de no conciliados	f	3	\N	65d01ddf-a052-525f-ad20-7c4f97d47674	68d0b9b0-fd93-5407-bd59-1ba92c00089c	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Umbral configurable por app	f	0	\N	a3d48f46-01d8-5bdb-84dd-f964edda97c6	68d7b410-e41e-596e-b25a-2c18a74aba73	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Scheduler de reintentos	t	0	\N	c3cf3314-78fe-559c-9873-95b06ff46b30	22a1ead3-b90e-5de6-b5d2-5eae56e585d0	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Panel de entregas fallidas	f	1	\N	c3cf3314-78fe-559c-9873-95b06ff46b30	c458219c-2924-50c5-b496-5f17bcd1ea27	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Canal WS /fleet/positions	t	0	\N	b7926d68-59ec-59a6-95e8-7f3a5b66eff0	f27a115e-3a29-5270-983a-f89815c10885	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Clustering de marcadores	f	1	\N	b7926d68-59ec-59a6-95e8-7f3a5b66eff0	4ddeb988-96d6-51d8-b66e-ba06e319e3c1	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
Modo ahorro de datos	f	2	\N	b7926d68-59ec-59a6-95e8-7f3a5b66eff0	bbf08a69-0bab-5432-93d1-55b8a97aaabb	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
\.


--
-- Data for Name: team_members; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.team_members (id, created_at, updated_at, team_id, user_id, name, email) FROM stdin;
\.


--
-- Data for Name: ticket_events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.ticket_events (ticket_id, user_id, event_type, detail, from_user_id, to_user_id, id, created_at, updated_at) FROM stdin;
ff906dcc-6ce8-5aae-996b-9be85bcc34c8	d04f9d09-e13f-51b1-885e-25836d43d4da	CREATED	{"beta_source": {"version": 1, "event_type": "CREATED", "event_index": 0, "ticket_alias": "t1", "ticket_status": "IN_PROGRESS"}}	\N	\N	d8d5ab39-47d9-579d-8dc3-c8bd7ba42b0c	2026-10-31 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
ff906dcc-6ce8-5aae-996b-9be85bcc34c8	d04f9d09-e13f-51b1-885e-25836d43d4da	ASSIGNED	{"to_user_id": "55dcf463-d79f-5297-81b2-b5f0ff3a6ee3", "beta_source": {"version": 1, "event_type": "ASSIGNED", "event_index": 1, "ticket_alias": "t1", "ticket_status": "IN_PROGRESS"}}	\N	55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	a804f14f-e972-581c-9c22-fa9e3a7861ee	2026-10-31 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
ff906dcc-6ce8-5aae-996b-9be85bcc34c8	55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	STATUS_CHANGED	{"to_status": "IN_PROGRESS", "beta_source": {"version": 1, "event_type": "STATUS", "event_index": 2, "ticket_alias": "t1", "ticket_status": "IN_PROGRESS"}, "from_status": "TODO"}	\N	\N	908f5922-2cf0-543d-a573-95be5a0781d0	2026-11-01 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
ff906dcc-6ce8-5aae-996b-9be85bcc34c8	d04f9d09-e13f-51b1-885e-25836d43d4da	COMMENT	{"message": "Prioriza la compatibilidad con 1Password, lo pidió el cliente.", "beta_source": {"version": 1, "event_type": "COMMENT", "event_index": 3, "ticket_alias": "t1", "ticket_status": "IN_PROGRESS"}}	\N	\N	0175e828-67f4-5b7b-9a5a-c561b067b4db	2026-11-03 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
e1b10ae9-d149-5156-98b5-4f12eee6876b	d04f9d09-e13f-51b1-885e-25836d43d4da	CREATED	{"beta_source": {"version": 1, "event_type": "CREATED", "event_index": 0, "ticket_alias": "t2", "ticket_status": "BLOCKED"}}	\N	\N	692ab867-dd2c-52ac-93cb-634a0e80a582	2026-10-29 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
e1b10ae9-d149-5156-98b5-4f12eee6876b	d04f9d09-e13f-51b1-885e-25836d43d4da	ASSIGNED	{"to_user_id": "3c212ba7-952f-5b91-8c3b-8d1247f2f8f0", "beta_source": {"version": 1, "event_type": "ASSIGNED", "event_index": 1, "ticket_alias": "t2", "ticket_status": "BLOCKED"}}	\N	3c212ba7-952f-5b91-8c3b-8d1247f2f8f0	11204c34-8a90-5a1b-a440-70e06f620041	2026-10-29 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
e1b10ae9-d149-5156-98b5-4f12eee6876b	3c212ba7-952f-5b91-8c3b-8d1247f2f8f0	QUESTION_RAISED	{"question": "¿El bloqueo aplica también a los accesos por API o solo al portal web?", "beta_source": {"version": 1, "event_type": "QUESTION", "event_index": 2, "ticket_alias": "t2", "ticket_status": "BLOCKED"}}	\N	\N	c274b030-89ae-5b6b-b8e1-1b1a0d8b5310	2026-11-04 12:23:28.440716+00	2026-11-04 17:23:28.440716+00
aff76bb6-eed7-5d32-9688-96a399c251b0	7f003437-a260-4abb-8620-c5ea3dcbf81e	CREATED	{"beta_source": {"version": 1, "event_type": "CREATED", "event_index": 0, "ticket_alias": "t3", "ticket_status": "TODO"}}	\N	\N	76c18626-1f6c-57fd-81f5-07fb1284443e	2026-11-02 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
cd40491d-432e-5a50-80b7-f5df98cf28c8	d04f9d09-e13f-51b1-885e-25836d43d4da	CREATED	{"beta_source": {"version": 1, "event_type": "CREATED", "event_index": 0, "ticket_alias": "t4", "ticket_status": "DONE"}}	\N	\N	4f5a11d8-f413-52db-9b8b-3c1779b24099	2026-10-26 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
cd40491d-432e-5a50-80b7-f5df98cf28c8	328890cb-25e5-5e9e-95f9-3a21950e4fe3	COMPLETED	{"pr_link": "https://github.com/wellq/portal/pull/412", "beta_source": {"version": 1, "event_type": "COMPLETED", "event_index": 1, "ticket_alias": "t4", "ticket_status": "DONE"}}	\N	\N	57f320ab-c382-519d-bf08-401efbd5c9f4	2026-11-03 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
65d01ddf-a052-525f-ad20-7c4f97d47674	d04f9d09-e13f-51b1-885e-25836d43d4da	CREATED	{"beta_source": {"version": 1, "event_type": "CREATED", "event_index": 0, "ticket_alias": "t5", "ticket_status": "IN_PROGRESS"}}	\N	\N	0edeeee1-d45c-5b40-9030-73de9245545a	2026-10-27 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
65d01ddf-a052-525f-ad20-7c4f97d47674	d04f9d09-e13f-51b1-885e-25836d43d4da	ASSIGNED	{"to_user_id": "3c212ba7-952f-5b91-8c3b-8d1247f2f8f0", "beta_source": {"version": 1, "event_type": "ASSIGNED", "event_index": 1, "ticket_alias": "t5", "ticket_status": "IN_PROGRESS"}}	\N	3c212ba7-952f-5b91-8c3b-8d1247f2f8f0	3af1e1e0-c730-5974-871f-94cc15e4cd35	2026-10-27 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
a3d48f46-01d8-5bdb-84dd-f964edda97c6	7f003437-a260-4abb-8620-c5ea3dcbf81e	CREATED	{"beta_source": {"version": 1, "event_type": "CREATED", "event_index": 0, "ticket_alias": "t6", "ticket_status": "TODO"}}	\N	\N	a59ee006-dc88-58a3-b2d8-af9432459007	2026-11-01 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
a3d48f46-01d8-5bdb-84dd-f964edda97c6	7f003437-a260-4abb-8620-c5ea3dcbf81e	ASSIGNED	{"to_user_id": "55dcf463-d79f-5297-81b2-b5f0ff3a6ee3", "beta_source": {"version": 1, "event_type": "ASSIGNED", "event_index": 1, "ticket_alias": "t6", "ticket_status": "TODO"}}	\N	55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	00636e54-8940-5be7-bea8-db77e47f7121	2026-11-01 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
c3cf3314-78fe-559c-9873-95b06ff46b30	d04f9d09-e13f-51b1-885e-25836d43d4da	CREATED	{"beta_source": {"version": 1, "event_type": "CREATED", "event_index": 0, "ticket_alias": "t7", "ticket_status": "REDIRECTED"}}	\N	\N	920a02d6-de1b-5c92-85ab-1a6fde4f8997	2026-10-28 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
c3cf3314-78fe-559c-9873-95b06ff46b30	328890cb-25e5-5e9e-95f9-3a21950e4fe3	REDIRECTED	{"to_user_id": "55dcf463-d79f-5297-81b2-b5f0ff3a6ee3", "beta_source": {"version": 1, "event_type": "REDIRECTED", "event_index": 1, "ticket_alias": "t7", "ticket_status": "REDIRECTED"}, "justification": "Necesita conocimiento del front del panel de entregas; Diego lo tiene fresco."}	328890cb-25e5-5e9e-95f9-3a21950e4fe3	55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	2eb7aaa6-0c6d-5c8a-ad13-28a43dc45be0	2026-11-02 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
b7926d68-59ec-59a6-95e8-7f3a5b66eff0	7f003437-a260-4abb-8620-c5ea3dcbf81e	CREATED	{"beta_source": {"version": 1, "event_type": "CREATED", "event_index": 0, "ticket_alias": "t8", "ticket_status": "IN_PROGRESS"}}	\N	\N	829706d0-c3dc-5719-94ac-b38600125845	2026-10-30 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
b7926d68-59ec-59a6-95e8-7f3a5b66eff0	7f003437-a260-4abb-8620-c5ea3dcbf81e	ASSIGNED	{"to_user_id": "328890cb-25e5-5e9e-95f9-3a21950e4fe3", "beta_source": {"version": 1, "event_type": "ASSIGNED", "event_index": 1, "ticket_alias": "t8", "ticket_status": "IN_PROGRESS"}}	\N	328890cb-25e5-5e9e-95f9-3a21950e4fe3	16f61a4b-c2a7-54a3-8b85-6b66f0f7b43b	2026-10-30 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
390c52e3-ade0-5c10-be70-21c49abd1a3f	7f003437-a260-4abb-8620-c5ea3dcbf81e	CREATED	{"beta_source": {"version": 1, "event_type": "CREATED", "event_index": 0, "ticket_alias": "t9", "ticket_status": "TODO"}}	\N	\N	05516028-b793-5455-8fad-3b9e55739f28	2026-11-03 17:23:28.440716+00	2026-11-04 17:23:28.440716+00
ccbe5567-8f20-4c58-b6cd-65debd7a988b	7f003437-a260-4abb-8620-c5ea3dcbf81e	CREATED	{"message": "Ticket creado por Ana Torres", "timestamp": "2026-11-06T01:51:15.704530+00:00"}	\N	\N	80d49cd6-bfeb-4e82-8a29-e0b80179b018	2026-11-06 01:51:15.696238+00	2026-11-06 01:51:15.696238+00
\.


--
-- PostgreSQL database dump complete
--

\unrestrict 3hcNgBUeGzhr0KggkIg8n9H9rxdGWPbChgwdNzFWu5RDs5Qpg7OGEPLfk0Tb8Er


-- users: hashed_password reemplazado por un valor que no valida ninguna contraseña
COPY public.users (id, email, hashed_password, full_name, avatar_url, specialty, is_active, role_id, created_at, updated_at, preferences, must_change_password) FROM stdin;
7f003437-a260-4abb-8620-c5ea3dcbf81e	a.torres@alloxentric.com	!SIN-HASH	Ana Torres	\N	Arquitectura de soluciones	t	80f15027-474b-4a48-8faf-32bff91d39ce	2026-11-04 01:57:53.634491+00	2026-11-04 17:23:58.237366+00	{"avatar_color": "#4C8DFF"}	f
55dcf463-d79f-5297-81b2-b5f0ff3a6ee3	d.ramos@alloxentric.com	!SIN-HASH	Diego Ramos	\N	Frontend · Vue / TypeScript	t	79b00b63-c6aa-4cfd-989f-fe23bafd57d5	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:58.237366+00	{"avatar_color": "#2FBF71"}	f
d04f9d09-e13f-51b1-885e-25836d43d4da	l.vega@alloxentric.com	!SIN-HASH	Luis Vega	\N	Backend · Líder equipo Pagos	t	3e03ec0d-b7f5-4eb0-a6d7-f00467c4649e	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:58.237366+00	{"avatar_color": "#8B7CF6"}	f
328890cb-25e5-5e9e-95f9-3a21950e4fe3	m.ibanez@alloxentric.com	!SIN-HASH	Marco Ibáñez	\N	QA · Automatización	t	79b00b63-c6aa-4cfd-989f-fe23bafd57d5	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:58.237366+00	{"avatar_color": "#F0554E"}	f
3c212ba7-952f-5b91-8c3b-8d1247f2f8f0	s.marquez@alloxentric.com	!SIN-HASH	Sofía Márquez	\N	Full-stack · Integraciones	t	79b00b63-c6aa-4cfd-989f-fe23bafd57d5	2026-11-04 17:23:28.440716+00	2026-11-04 17:23:58.237366+00	{"avatar_color": "#F2A93B"}	f
\.

SET session_replication_role = DEFAULT;
