--
-- PostgreSQL database dump
--

\restrict 2sXFfO7v3phO1KZvMbR52ifIKMTTcndKHcUXCsKCsFfNjVi8Brt7Bhfvojg3YWu

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
-- Name: attendance_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.attendance_status_enum AS ENUM (
    'PRESENT',
    'ABSENT',
    'JUSTIFIED'
);


--
-- Name: document_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.document_type_enum AS ENUM (
    'CODE',
    'DOCUMENTATION'
);


--
-- Name: incident_environment_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.incident_environment_enum AS ENUM (
    'PRODUCTION',
    'STAGING',
    'DEV'
);


--
-- Name: incident_severity_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.incident_severity_enum AS ENUM (
    'P1',
    'P2',
    'P3'
);


--
-- Name: incident_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.incident_status_enum AS ENUM (
    'REPORTED',
    'INVESTIGATING',
    'MITIGATED',
    'RESOLVED'
);


--
-- Name: meeting_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.meeting_type_enum AS ENUM (
    'DAILY',
    'PLANNING',
    'RETROSPECTIVE',
    'OTHER'
);


--
-- Name: notification_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.notification_type_enum AS ENUM (
    'ASSIGNMENT',
    'QUESTION',
    'REDIRECT',
    'COMPLETION',
    'SYSTEM',
    'TICKET_ASSIGNED',
    'STATUS_CHANGED',
    'TICKET_REDIRECTED',
    'TICKET_COMPLETED',
    'QUESTION_RAISED'
);


--
-- Name: support_severity_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.support_severity_enum AS ENUM (
    'CRITICAL',
    'HIGH',
    'MEDIUM',
    'LOW'
);


--
-- Name: ticket_event_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.ticket_event_type_enum AS ENUM (
    'CREATED',
    'ASSIGNED',
    'STATUS_CHANGED',
    'QUESTION_RAISED',
    'QUESTION_RESOLVED',
    'REDIRECTED',
    'COMPLETED',
    'COMMENT',
    'TIMER_START',
    'TIMER_PAUSE',
    'UPDATED',
    'SUBTASK_CREATED',
    'SUBTASK_COMPLETED',
    'SUBTASK_DELETED',
    'TICKET_ASSIGNED',
    'MOVED'
);


--
-- Name: ticket_priority_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.ticket_priority_enum AS ENUM (
    'LOW',
    'MEDIUM',
    'HIGH',
    'URGENT'
);


--
-- Name: ticket_status_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.ticket_status_enum AS ENUM (
    'TODO',
    'IN_PROGRESS',
    'BLOCKED',
    'REDIRECTED',
    'COMPLETED',
    'BLOCKED_QUESTION',
    'REPORTED',
    'INVESTIGATING',
    'RESOLVED'
);


--
-- Name: ticket_type_enum; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.ticket_type_enum AS ENUM (
    'DEVELOPMENT',
    'SUPPORT'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: alembic_version; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alembic_version (
    version_num character varying(32) NOT NULL
);


--
-- Name: applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.applications (
    name character varying(255) NOT NULL,
    description character varying(1000),
    color character varying(7),
    icon character varying(255),
    is_active boolean NOT NULL,
    owner_id uuid,
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.documents (
    filename character varying(255) NOT NULL,
    file_path character varying(512) NOT NULL,
    file_size integer NOT NULL,
    mime_type character varying(100) NOT NULL,
    doc_type public.document_type_enum NOT NULL,
    epic_id uuid,
    ticket_id uuid,
    uploaded_by_id uuid,
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_documents_has_target CHECK (((epic_id IS NOT NULL) OR (ticket_id IS NOT NULL)))
);


--
-- Name: epics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.epics (
    title character varying(255) NOT NULL,
    description character varying(2000),
    order_index integer NOT NULL,
    due_date timestamp with time zone,
    is_collapsed boolean NOT NULL,
    application_id uuid NOT NULL,
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    team_id uuid
);


--
-- Name: incidents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.incidents (
    title character varying(255) NOT NULL,
    description text,
    status public.incident_status_enum NOT NULL,
    severity public.incident_severity_enum NOT NULL,
    affected_environment public.incident_environment_enum NOT NULL,
    estimated_resolution_time_seconds integer NOT NULL,
    mitigation_state text,
    application_id uuid,
    created_by_id uuid,
    assigned_to_id uuid,
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    email character varying(255) NOT NULL,
    token_hash character varying(64) NOT NULL,
    role character varying(50) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    used_at timestamp with time zone,
    created_by_id uuid
);


--
-- Name: meeting_attendances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meeting_attendances (
    meeting_id uuid NOT NULL,
    user_id uuid NOT NULL,
    status public.attendance_status_enum NOT NULL,
    notes text,
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: meetings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meetings (
    title character varying(255) NOT NULL,
    meeting_type public.meeting_type_enum NOT NULL,
    scheduled_at timestamp with time zone NOT NULL,
    summary_markdown text,
    application_id uuid,
    created_by_id uuid,
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    user_id uuid NOT NULL,
    ticket_id uuid,
    title character varying(255) NOT NULL,
    message character varying(1000) NOT NULL,
    type public.notification_type_enum NOT NULL,
    is_read boolean NOT NULL,
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    read_at timestamp with time zone
);


--
-- Name: password_reset_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.password_reset_tokens (
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid NOT NULL,
    token_hash character varying(64) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    used_at timestamp with time zone
);


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    name character varying(50) NOT NULL,
    description character varying(255),
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: subtasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subtasks (
    title character varying(255) NOT NULL,
    is_completed boolean NOT NULL,
    order_index integer NOT NULL,
    completed_at timestamp with time zone,
    ticket_id uuid NOT NULL,
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: team_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_members (
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    team_id uuid NOT NULL,
    user_id uuid,
    name character varying(255) NOT NULL,
    email character varying(255)
);


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    name character varying(255) NOT NULL,
    description character varying(1000)
);


--
-- Name: ticket_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ticket_events (
    ticket_id uuid NOT NULL,
    user_id uuid,
    event_type public.ticket_event_type_enum NOT NULL,
    detail jsonb,
    from_user_id uuid,
    to_user_id uuid,
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tickets (
    title character varying(255) NOT NULL,
    description character varying(3000),
    status public.ticket_status_enum NOT NULL,
    priority public.ticket_priority_enum NOT NULL,
    order_index integer NOT NULL,
    due_date timestamp with time zone,
    pr_link character varying(512),
    time_spent_seconds integer NOT NULL,
    blocked_time_seconds integer NOT NULL,
    epic_id uuid,
    assignee_id uuid,
    created_by_id uuid,
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    block_reason character varying(1000),
    estimated_time_seconds integer NOT NULL,
    completed_at timestamp with time zone,
    blocked_question character varying(1000),
    blocked_at timestamp with time zone,
    timer_started_at timestamp with time zone,
    ticket_type public.ticket_type_enum DEFAULT 'DEVELOPMENT'::public.ticket_type_enum NOT NULL,
    stack_trace text,
    reproduction_steps text,
    browser character varying(100),
    operating_system character varying(100),
    severity public.support_severity_enum,
    linked_ticket_id uuid
);


--
-- Name: user_devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_devices (
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    user_id uuid NOT NULL,
    token character varying(4096) NOT NULL,
    platform character varying(20) NOT NULL,
    is_active boolean NOT NULL,
    last_seen_at timestamp with time zone NOT NULL,
    deactivated_at timestamp with time zone,
    device_name character varying(120),
    app_version character varying(20)
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    email character varying(255) NOT NULL,
    hashed_password character varying(255) NOT NULL,
    full_name character varying(255) NOT NULL,
    avatar_url character varying(512),
    specialty character varying(255),
    is_active boolean NOT NULL,
    role_id uuid NOT NULL,
    id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    preferences json,
    must_change_password boolean DEFAULT false NOT NULL
);


--
-- Name: alembic_version alembic_version_pkc; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alembic_version
    ADD CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num);


--
-- Name: applications applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applications
    ADD CONSTRAINT applications_pkey PRIMARY KEY (id);


--
-- Name: documents documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_pkey PRIMARY KEY (id);


--
-- Name: epics epics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.epics
    ADD CONSTRAINT epics_pkey PRIMARY KEY (id);


--
-- Name: incidents incidents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT incidents_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_token_hash_key UNIQUE (token_hash);


--
-- Name: meeting_attendances meeting_attendances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meeting_attendances
    ADD CONSTRAINT meeting_attendances_pkey PRIMARY KEY (id);


--
-- Name: meetings meetings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meetings
    ADD CONSTRAINT meetings_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: password_reset_tokens password_reset_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_pkey PRIMARY KEY (id);


--
-- Name: password_reset_tokens password_reset_tokens_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_token_hash_key UNIQUE (token_hash);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: subtasks subtasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subtasks
    ADD CONSTRAINT subtasks_pkey PRIMARY KEY (id);


--
-- Name: team_members team_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_pkey PRIMARY KEY (id);


--
-- Name: teams teams_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_name_key UNIQUE (name);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: ticket_events ticket_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_events
    ADD CONSTRAINT ticket_events_pkey PRIMARY KEY (id);


--
-- Name: tickets tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_pkey PRIMARY KEY (id);


--
-- Name: user_devices uq_user_devices_token; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_devices
    ADD CONSTRAINT uq_user_devices_token UNIQUE (token);


--
-- Name: user_devices user_devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_devices
    ADD CONSTRAINT user_devices_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: ix_applications_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_applications_created_at ON public.applications USING btree (created_at);


--
-- Name: ix_applications_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_applications_is_active ON public.applications USING btree (is_active);


--
-- Name: ix_applications_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_applications_name ON public.applications USING btree (name);


--
-- Name: ix_applications_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_applications_owner_id ON public.applications USING btree (owner_id);


--
-- Name: ix_documents_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_documents_created_at ON public.documents USING btree (created_at);


--
-- Name: ix_documents_epic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_documents_epic_id ON public.documents USING btree (epic_id);


--
-- Name: ix_documents_ticket_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_documents_ticket_id ON public.documents USING btree (ticket_id);


--
-- Name: ix_documents_uploaded_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_documents_uploaded_by_id ON public.documents USING btree (uploaded_by_id);


--
-- Name: ix_epics_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_epics_application_id ON public.epics USING btree (application_id);


--
-- Name: ix_epics_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_epics_created_at ON public.epics USING btree (created_at);


--
-- Name: ix_epics_order_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_epics_order_index ON public.epics USING btree (order_index);


--
-- Name: ix_epics_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_epics_team_id ON public.epics USING btree (team_id);


--
-- Name: ix_incidents_affected_environment; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_incidents_affected_environment ON public.incidents USING btree (affected_environment);


--
-- Name: ix_incidents_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_incidents_application_id ON public.incidents USING btree (application_id);


--
-- Name: ix_incidents_assigned_to_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_incidents_assigned_to_id ON public.incidents USING btree (assigned_to_id);


--
-- Name: ix_incidents_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_incidents_created_at ON public.incidents USING btree (created_at);


--
-- Name: ix_incidents_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_incidents_created_by_id ON public.incidents USING btree (created_by_id);


--
-- Name: ix_incidents_severity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_incidents_severity ON public.incidents USING btree (severity);


--
-- Name: ix_incidents_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_incidents_status ON public.incidents USING btree (status);


--
-- Name: ix_invitations_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_invitations_email ON public.invitations USING btree (email);


--
-- Name: ix_invitations_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_invitations_token_hash ON public.invitations USING btree (token_hash);


--
-- Name: ix_meeting_attendances_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_meeting_attendances_created_at ON public.meeting_attendances USING btree (created_at);


--
-- Name: ix_meeting_attendances_meeting_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_meeting_attendances_meeting_id ON public.meeting_attendances USING btree (meeting_id);


--
-- Name: ix_meeting_attendances_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_meeting_attendances_user_id ON public.meeting_attendances USING btree (user_id);


--
-- Name: ix_meetings_application_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_meetings_application_id ON public.meetings USING btree (application_id);


--
-- Name: ix_meetings_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_meetings_created_at ON public.meetings USING btree (created_at);


--
-- Name: ix_meetings_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_meetings_created_by_id ON public.meetings USING btree (created_by_id);


--
-- Name: ix_meetings_meeting_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_meetings_meeting_type ON public.meetings USING btree (meeting_type);


--
-- Name: ix_notifications_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_notifications_created_at ON public.notifications USING btree (created_at);


--
-- Name: ix_notifications_is_read; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_notifications_is_read ON public.notifications USING btree (is_read);


--
-- Name: ix_notifications_ticket_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_notifications_ticket_id ON public.notifications USING btree (ticket_id);


--
-- Name: ix_notifications_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_notifications_user_id ON public.notifications USING btree (user_id);


--
-- Name: ix_password_reset_tokens_token_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_password_reset_tokens_token_hash ON public.password_reset_tokens USING btree (token_hash);


--
-- Name: ix_password_reset_tokens_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_password_reset_tokens_user_id ON public.password_reset_tokens USING btree (user_id);


--
-- Name: ix_roles_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_roles_created_at ON public.roles USING btree (created_at);


--
-- Name: ix_roles_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_roles_name ON public.roles USING btree (name);


--
-- Name: ix_subtasks_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_subtasks_created_at ON public.subtasks USING btree (created_at);


--
-- Name: ix_subtasks_is_completed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_subtasks_is_completed ON public.subtasks USING btree (is_completed);


--
-- Name: ix_subtasks_ticket_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_subtasks_ticket_id ON public.subtasks USING btree (ticket_id);


--
-- Name: ix_team_members_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_team_members_created_at ON public.team_members USING btree (created_at);


--
-- Name: ix_team_members_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_team_members_team_id ON public.team_members USING btree (team_id);


--
-- Name: ix_team_members_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_team_members_user_id ON public.team_members USING btree (user_id);


--
-- Name: ix_teams_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_teams_created_at ON public.teams USING btree (created_at);


--
-- Name: ix_teams_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_teams_name ON public.teams USING btree (name);


--
-- Name: ix_ticket_events_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ticket_events_created_at ON public.ticket_events USING btree (created_at);


--
-- Name: ix_ticket_events_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ticket_events_event_type ON public.ticket_events USING btree (event_type);


--
-- Name: ix_ticket_events_ticket_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ticket_events_ticket_id ON public.ticket_events USING btree (ticket_id);


--
-- Name: ix_ticket_events_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_ticket_events_user_id ON public.ticket_events USING btree (user_id);


--
-- Name: ix_tickets_assignee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tickets_assignee_id ON public.tickets USING btree (assignee_id);


--
-- Name: ix_tickets_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tickets_created_at ON public.tickets USING btree (created_at);


--
-- Name: ix_tickets_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tickets_created_by_id ON public.tickets USING btree (created_by_id);


--
-- Name: ix_tickets_epic_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tickets_epic_id ON public.tickets USING btree (epic_id);


--
-- Name: ix_tickets_order_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tickets_order_index ON public.tickets USING btree (order_index);


--
-- Name: ix_tickets_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tickets_priority ON public.tickets USING btree (priority);


--
-- Name: ix_tickets_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tickets_status ON public.tickets USING btree (status);


--
-- Name: ix_tickets_ticket_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_tickets_ticket_type ON public.tickets USING btree (ticket_type);


--
-- Name: ix_user_devices_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_user_devices_created_at ON public.user_devices USING btree (created_at);


--
-- Name: ix_user_devices_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_user_devices_is_active ON public.user_devices USING btree (is_active);


--
-- Name: ix_user_devices_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_user_devices_user_id ON public.user_devices USING btree (user_id);


--
-- Name: ix_users_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_users_created_at ON public.users USING btree (created_at);


--
-- Name: ix_users_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_users_email ON public.users USING btree (email);


--
-- Name: ix_users_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_users_is_active ON public.users USING btree (is_active);


--
-- Name: ix_users_role_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_users_role_id ON public.users USING btree (role_id);


--
-- Name: applications applications_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applications
    ADD CONSTRAINT applications_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: documents documents_epic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_epic_id_fkey FOREIGN KEY (epic_id) REFERENCES public.epics(id) ON DELETE CASCADE;


--
-- Name: documents documents_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.tickets(id) ON DELETE CASCADE;


--
-- Name: documents documents_uploaded_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.documents
    ADD CONSTRAINT documents_uploaded_by_id_fkey FOREIGN KEY (uploaded_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: epics epics_application_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.epics
    ADD CONSTRAINT epics_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.applications(id) ON DELETE CASCADE;


--
-- Name: epics fk_epics_team_id_teams; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.epics
    ADD CONSTRAINT fk_epics_team_id_teams FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE SET NULL;


--
-- Name: incidents incidents_application_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT incidents_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.applications(id) ON DELETE SET NULL;


--
-- Name: incidents incidents_assigned_to_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT incidents_assigned_to_id_fkey FOREIGN KEY (assigned_to_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: incidents incidents_created_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT incidents_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: invitations invitations_created_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: meeting_attendances meeting_attendances_meeting_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meeting_attendances
    ADD CONSTRAINT meeting_attendances_meeting_id_fkey FOREIGN KEY (meeting_id) REFERENCES public.meetings(id) ON DELETE CASCADE;


--
-- Name: meeting_attendances meeting_attendances_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meeting_attendances
    ADD CONSTRAINT meeting_attendances_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: meetings meetings_application_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meetings
    ADD CONSTRAINT meetings_application_id_fkey FOREIGN KEY (application_id) REFERENCES public.applications(id) ON DELETE CASCADE;


--
-- Name: meetings meetings_created_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meetings
    ADD CONSTRAINT meetings_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: notifications notifications_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.tickets(id) ON DELETE SET NULL;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: password_reset_tokens password_reset_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.password_reset_tokens
    ADD CONSTRAINT password_reset_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: subtasks subtasks_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subtasks
    ADD CONSTRAINT subtasks_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.tickets(id) ON DELETE CASCADE;


--
-- Name: team_members team_members_team_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_team_id_fkey FOREIGN KEY (team_id) REFERENCES public.teams(id) ON DELETE CASCADE;


--
-- Name: team_members team_members_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_members
    ADD CONSTRAINT team_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: ticket_events ticket_events_from_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_events
    ADD CONSTRAINT ticket_events_from_user_id_fkey FOREIGN KEY (from_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: ticket_events ticket_events_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_events
    ADD CONSTRAINT ticket_events_ticket_id_fkey FOREIGN KEY (ticket_id) REFERENCES public.tickets(id) ON DELETE CASCADE;


--
-- Name: ticket_events ticket_events_to_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_events
    ADD CONSTRAINT ticket_events_to_user_id_fkey FOREIGN KEY (to_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: ticket_events ticket_events_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ticket_events
    ADD CONSTRAINT ticket_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: tickets tickets_assignee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_assignee_id_fkey FOREIGN KEY (assignee_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: tickets tickets_created_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: tickets tickets_epic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_epic_id_fkey FOREIGN KEY (epic_id) REFERENCES public.epics(id) ON DELETE CASCADE;


--
-- Name: tickets tickets_linked_ticket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tickets
    ADD CONSTRAINT tickets_linked_ticket_id_fkey FOREIGN KEY (linked_ticket_id) REFERENCES public.tickets(id) ON DELETE SET NULL;


--
-- Name: user_devices user_devices_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_devices
    ADD CONSTRAINT user_devices_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: users users_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict 2sXFfO7v3phO1KZvMbR52ifIKMTTcndKHcUXCsKCsFfNjVi8Brt7Bhfvojg3YWu

