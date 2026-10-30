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
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: EXTENSION btree_gist; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION btree_gist IS 'support for indexing common datatypes in GiST';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: appointment_status_histories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appointment_status_histories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    appointment_id uuid NOT NULL,
    from_status character varying,
    to_status character varying NOT NULL,
    changed_at timestamp with time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: appointments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appointments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    vehicle_id uuid NOT NULL,
    technician_id uuid NOT NULL,
    service_bay_id uuid NOT NULL,
    service_type_id uuid NOT NULL,
    dealership_id uuid NOT NULL,
    start_at timestamp with time zone NOT NULL,
    end_at timestamp with time zone NOT NULL,
    status character varying DEFAULT 'confirmed'::character varying NOT NULL,
    lock_version integer DEFAULT 0 NOT NULL,
    time_range tstzrange GENERATED ALWAYS AS (tstzrange(start_at, end_at, '[)'::text)) STORED,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT appointments_end_after_start_check CHECK ((end_at > start_at)),
    CONSTRAINT appointments_status_check CHECK (((status)::text = ANY ((ARRAY['confirmed'::character varying, 'in_progress'::character varying, 'completed'::character varying, 'cancelled'::character varying, 'no_show'::character varying])::text[])))
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: bay_blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bay_blocks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    service_bay_id uuid NOT NULL,
    start_at timestamp with time zone NOT NULL,
    end_at timestamp with time zone NOT NULL,
    reason character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT bay_blocks_end_after_start_check CHECK ((end_at > start_at))
);


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    email character varying NOT NULL,
    phone character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: dealership_holidays; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dealership_holidays (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    dealership_id uuid NOT NULL,
    holiday_on date NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: dealership_opening_hours; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dealership_opening_hours (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    dealership_id uuid NOT NULL,
    day_of_week integer NOT NULL,
    opens_at time without time zone NOT NULL,
    closes_at time without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT dealership_opening_hours_closes_after_opens_check CHECK ((closes_at > opens_at)),
    CONSTRAINT dealership_opening_hours_day_of_week_check CHECK (((day_of_week >= 0) AND (day_of_week <= 6)))
);


--
-- Name: dealerships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dealerships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    time_zone character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: idempotency_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.idempotency_keys (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key character varying NOT NULL,
    request_fingerprint character varying NOT NULL,
    appointment_id uuid,
    response_status integer,
    response_body jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: qualifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.qualifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code character varying NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: service_bays; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_bays (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    dealership_id uuid NOT NULL,
    name character varying NOT NULL,
    bay_type character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT service_bays_bay_type_check CHECK (((bay_type)::text = ANY ((ARRAY['general'::character varying, 'lift'::character varying, 'alignment'::character varying])::text[])))
);


--
-- Name: service_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_types (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    duration_minutes integer NOT NULL,
    required_qualification_id uuid,
    required_bay_type character varying DEFAULT 'general'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT service_types_duration_minutes_check CHECK ((duration_minutes > 0)),
    CONSTRAINT service_types_required_bay_type_check CHECK (((required_bay_type)::text = ANY ((ARRAY['general'::character varying, 'lift'::character varying, 'alignment'::character varying])::text[])))
);


--
-- Name: technician_qualifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.technician_qualifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    technician_id uuid NOT NULL,
    qualification_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: technician_shifts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.technician_shifts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    technician_id uuid NOT NULL,
    day_of_week integer NOT NULL,
    starts_at time without time zone NOT NULL,
    ends_at time without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT technician_shifts_day_of_week_check CHECK (((day_of_week >= 0) AND (day_of_week <= 6))),
    CONSTRAINT technician_shifts_ends_after_starts_check CHECK ((ends_at > starts_at))
);


--
-- Name: technician_time_off; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.technician_time_off (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    technician_id uuid NOT NULL,
    start_at timestamp with time zone NOT NULL,
    end_at timestamp with time zone NOT NULL,
    reason character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT technician_time_off_end_after_start_check CHECK ((end_at > start_at))
);


--
-- Name: technicians; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.technicians (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    dealership_id uuid NOT NULL,
    name character varying NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: vehicles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vehicles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    customer_id uuid NOT NULL,
    vin character varying NOT NULL,
    make character varying NOT NULL,
    model character varying NOT NULL,
    year integer,
    license_plate character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: appointment_status_histories appointment_status_histories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointment_status_histories
    ADD CONSTRAINT appointment_status_histories_pkey PRIMARY KEY (id);


--
-- Name: appointments appointments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: bay_blocks bay_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bay_blocks
    ADD CONSTRAINT bay_blocks_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: dealership_holidays dealership_holidays_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dealership_holidays
    ADD CONSTRAINT dealership_holidays_pkey PRIMARY KEY (id);


--
-- Name: dealership_opening_hours dealership_opening_hours_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dealership_opening_hours
    ADD CONSTRAINT dealership_opening_hours_pkey PRIMARY KEY (id);


--
-- Name: dealerships dealerships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dealerships
    ADD CONSTRAINT dealerships_pkey PRIMARY KEY (id);


--
-- Name: idempotency_keys idempotency_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT idempotency_keys_pkey PRIMARY KEY (id);


--
-- Name: qualifications qualifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qualifications
    ADD CONSTRAINT qualifications_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: service_bays service_bays_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_bays
    ADD CONSTRAINT service_bays_pkey PRIMARY KEY (id);


--
-- Name: service_types service_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_types
    ADD CONSTRAINT service_types_pkey PRIMARY KEY (id);


--
-- Name: technician_qualifications technician_qualifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_qualifications
    ADD CONSTRAINT technician_qualifications_pkey PRIMARY KEY (id);


--
-- Name: technician_shifts technician_shifts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_shifts
    ADD CONSTRAINT technician_shifts_pkey PRIMARY KEY (id);


--
-- Name: technician_time_off technician_time_off_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_time_off
    ADD CONSTRAINT technician_time_off_pkey PRIMARY KEY (id);


--
-- Name: technicians technicians_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technicians
    ADD CONSTRAINT technicians_pkey PRIMARY KEY (id);


--
-- Name: vehicles vehicles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT vehicles_pkey PRIMARY KEY (id);


--
-- Name: idx_on_dealership_id_day_of_week_41c682f7d2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_dealership_id_day_of_week_41c682f7d2 ON public.dealership_opening_hours USING btree (dealership_id, day_of_week);


--
-- Name: idx_on_technician_id_qualification_id_3c8d696923; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_technician_id_qualification_id_3c8d696923 ON public.technician_qualifications USING btree (technician_id, qualification_id);


--
-- Name: index_appointment_status_histories_on_appointment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointment_status_histories_on_appointment_id ON public.appointment_status_histories USING btree (appointment_id);


--
-- Name: index_appointments_on_customer_id_and_start_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_customer_id_and_start_at ON public.appointments USING btree (customer_id, start_at);


--
-- Name: index_appointments_on_dealership_id_and_start_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_dealership_id_and_start_at ON public.appointments USING btree (dealership_id, start_at);


--
-- Name: index_appointments_on_service_bay_id_and_time_range; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_service_bay_id_and_time_range ON public.appointments USING gist (service_bay_id, time_range);


--
-- Name: index_appointments_on_service_type_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_service_type_id ON public.appointments USING btree (service_type_id);


--
-- Name: index_appointments_on_technician_id_and_time_range; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_technician_id_and_time_range ON public.appointments USING gist (technician_id, time_range);


--
-- Name: index_appointments_on_vehicle_id_and_start_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_vehicle_id_and_start_at ON public.appointments USING btree (vehicle_id, start_at);


--
-- Name: index_bay_blocks_on_service_bay_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bay_blocks_on_service_bay_id ON public.bay_blocks USING btree (service_bay_id);


--
-- Name: index_bay_blocks_on_service_bay_id_and_start_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bay_blocks_on_service_bay_id_and_start_at ON public.bay_blocks USING btree (service_bay_id, start_at);


--
-- Name: index_customers_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_customers_on_email ON public.customers USING btree (email);


--
-- Name: index_dealership_holidays_on_dealership_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_dealership_holidays_on_dealership_id ON public.dealership_holidays USING btree (dealership_id);


--
-- Name: index_dealership_holidays_on_dealership_id_and_holiday_on; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_dealership_holidays_on_dealership_id_and_holiday_on ON public.dealership_holidays USING btree (dealership_id, holiday_on);


--
-- Name: index_dealership_opening_hours_on_dealership_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_dealership_opening_hours_on_dealership_id ON public.dealership_opening_hours USING btree (dealership_id);


--
-- Name: index_idempotency_keys_on_appointment_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_idempotency_keys_on_appointment_id ON public.idempotency_keys USING btree (appointment_id);


--
-- Name: index_idempotency_keys_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_idempotency_keys_on_key ON public.idempotency_keys USING btree (key);


--
-- Name: index_qualifications_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_qualifications_on_code ON public.qualifications USING btree (code);


--
-- Name: index_service_bays_on_dealership_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_service_bays_on_dealership_id ON public.service_bays USING btree (dealership_id);


--
-- Name: index_service_bays_on_dealership_id_and_bay_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_service_bays_on_dealership_id_and_bay_type ON public.service_bays USING btree (dealership_id, bay_type);


--
-- Name: index_service_types_on_required_qualification_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_service_types_on_required_qualification_id ON public.service_types USING btree (required_qualification_id);


--
-- Name: index_technician_qualifications_on_qualification_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_technician_qualifications_on_qualification_id ON public.technician_qualifications USING btree (qualification_id);


--
-- Name: index_technician_qualifications_on_technician_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_technician_qualifications_on_technician_id ON public.technician_qualifications USING btree (technician_id);


--
-- Name: index_technician_shifts_on_technician_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_technician_shifts_on_technician_id ON public.technician_shifts USING btree (technician_id);


--
-- Name: index_technician_shifts_on_technician_id_and_day_of_week; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_technician_shifts_on_technician_id_and_day_of_week ON public.technician_shifts USING btree (technician_id, day_of_week);


--
-- Name: index_technician_time_off_on_technician_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_technician_time_off_on_technician_id ON public.technician_time_off USING btree (technician_id);


--
-- Name: index_technician_time_off_on_technician_id_and_start_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_technician_time_off_on_technician_id_and_start_at ON public.technician_time_off USING btree (technician_id, start_at);


--
-- Name: index_technicians_on_dealership_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_technicians_on_dealership_id ON public.technicians USING btree (dealership_id);


--
-- Name: index_vehicles_on_customer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vehicles_on_customer_id ON public.vehicles USING btree (customer_id);


--
-- Name: index_vehicles_on_vin; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_vehicles_on_vin ON public.vehicles USING btree (vin);


--
-- Name: technician_time_off fk_rails_05f52c6eb8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_time_off
    ADD CONSTRAINT fk_rails_05f52c6eb8 FOREIGN KEY (technician_id) REFERENCES public.technicians(id);


--
-- Name: appointments fk_rails_06a7a75113; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_06a7a75113 FOREIGN KEY (vehicle_id) REFERENCES public.vehicles(id);


--
-- Name: dealership_holidays fk_rails_13a7ed7900; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dealership_holidays
    ADD CONSTRAINT fk_rails_13a7ed7900 FOREIGN KEY (dealership_id) REFERENCES public.dealerships(id);


--
-- Name: dealership_opening_hours fk_rails_225aae9920; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dealership_opening_hours
    ADD CONSTRAINT fk_rails_225aae9920 FOREIGN KEY (dealership_id) REFERENCES public.dealerships(id);


--
-- Name: service_bays fk_rails_332a1dff85; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_bays
    ADD CONSTRAINT fk_rails_332a1dff85 FOREIGN KEY (dealership_id) REFERENCES public.dealerships(id);


--
-- Name: bay_blocks fk_rails_3c78f8463c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bay_blocks
    ADD CONSTRAINT fk_rails_3c78f8463c FOREIGN KEY (service_bay_id) REFERENCES public.service_bays(id);


--
-- Name: technicians fk_rails_4a9cbc4f1d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technicians
    ADD CONSTRAINT fk_rails_4a9cbc4f1d FOREIGN KEY (dealership_id) REFERENCES public.dealerships(id);


--
-- Name: service_types fk_rails_62286c4da3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_types
    ADD CONSTRAINT fk_rails_62286c4da3 FOREIGN KEY (required_qualification_id) REFERENCES public.qualifications(id);


--
-- Name: appointments fk_rails_66eec7e323; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_66eec7e323 FOREIGN KEY (service_bay_id) REFERENCES public.service_bays(id);


--
-- Name: appointments fk_rails_671ea90d9f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_671ea90d9f FOREIGN KEY (dealership_id) REFERENCES public.dealerships(id);


--
-- Name: appointment_status_histories fk_rails_7ac4d5ce03; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointment_status_histories
    ADD CONSTRAINT fk_rails_7ac4d5ce03 FOREIGN KEY (appointment_id) REFERENCES public.appointments(id);


--
-- Name: appointments fk_rails_882571afb2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_882571afb2 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: technician_qualifications fk_rails_8e948b21ac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_qualifications
    ADD CONSTRAINT fk_rails_8e948b21ac FOREIGN KEY (qualification_id) REFERENCES public.qualifications(id);


--
-- Name: appointments fk_rails_959fbcc528; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_959fbcc528 FOREIGN KEY (technician_id) REFERENCES public.technicians(id);


--
-- Name: appointments fk_rails_aa25fc3e44; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_aa25fc3e44 FOREIGN KEY (service_type_id) REFERENCES public.service_types(id);


--
-- Name: technician_qualifications fk_rails_c99d8685a1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_qualifications
    ADD CONSTRAINT fk_rails_c99d8685a1 FOREIGN KEY (technician_id) REFERENCES public.technicians(id);


--
-- Name: vehicles fk_rails_d717085634; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vehicles
    ADD CONSTRAINT fk_rails_d717085634 FOREIGN KEY (customer_id) REFERENCES public.customers(id);


--
-- Name: technician_shifts fk_rails_d986b3da8e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technician_shifts
    ADD CONSTRAINT fk_rails_d986b3da8e FOREIGN KEY (technician_id) REFERENCES public.technicians(id);


--
-- Name: idempotency_keys fk_rails_df840d2995; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.idempotency_keys
    ADD CONSTRAINT fk_rails_df840d2995 FOREIGN KEY (appointment_id) REFERENCES public.appointments(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260101000005'),
('20260101000004'),
('20260101000003'),
('20260101000002'),
('20260101000001');

