use rusqlite::{Connection, OptionalExtension, params, params_from_iter};

use crate::{
    GooseError, GooseResult,
    protocol::{DataPacketBodySummary, ParsedPayload},
};

use super::{
    BackfillReport, CaptureSessionInput, CaptureSessionRow, DecodedFrameInput, DecodedFrameRow,
    GooseStore, OvernightHistoricalRangePollInput, OvernightMirrorCounts, OvernightMirrorReport,
    OvernightRawNotificationInput, OvernightSyncSessionInput, RawEvidenceInput,
    RawEvidencePayloadRetentionReport, RawEvidenceRow, RrIntervalRow, STREAM_ALLOWLIST,
    StepCounterSampleInput, StepCounterSampleRow, bool_to_i64, capture_session_from_row,
    decoded_frame_from_row, device_type_name, sha256_hex, step_counter_sample_from_row,
    unix_f64_to_iso8601, validate_json_object, validate_non_negative, validate_required,
    validate_step_counter_sample_input, validate_window_order,
};

impl GooseStore {
    pub fn mirror_overnight_batch(
        &self,
        sessions: &[OvernightSyncSessionInput<'_>],
        raw_notifications: &[OvernightRawNotificationInput<'_>],
        historical_range_polls: &[OvernightHistoricalRangePollInput<'_>],
    ) -> GooseResult<OvernightMirrorReport> {
        // Ensure tables exist before acquiring the transaction lock
        self.ensure_overnight_mirror_tables()?;
        self.immediate_transaction(|conn| {
            let mut report = OvernightMirrorReport {
                schema: "goose.overnight-mirror-report.v1".to_string(),
                session_upserted: 0,
                raw_inserted: 0,
                raw_existing: 0,
                historical_range_inserted: 0,
                historical_range_existing: 0,
                issues: Vec::new(),
            };

            for session in sessions {
                match Self::upsert_overnight_sync_session_with_conn(conn, session) {
                    Ok(true) => report.session_upserted += 1,
                    Ok(false) => {}
                    Err(error) => report
                        .issues
                        .push(format!("session {} failed: {error}", session.session_id)),
                }
            }

            for notification in raw_notifications {
                match Self::insert_overnight_raw_notification_with_conn(conn, notification) {
                    Ok(true) => report.raw_inserted += 1,
                    Ok(false) => report.raw_existing += 1,
                    Err(error) => report.issues.push(format!(
                        "raw notification {} {} failed: {error}",
                        notification.session_id, notification.captured_at
                    )),
                }
            }

            for poll in historical_range_polls {
                match Self::insert_overnight_historical_range_poll_with_conn(conn, poll) {
                    Ok(true) => report.historical_range_inserted += 1,
                    Ok(false) => report.historical_range_existing += 1,
                    Err(error) => report.issues.push(format!(
                        "historical range {} {} seq {} failed: {error}",
                        poll.session_id, poll.captured_at, poll.command_sequence
                    )),
                }
            }

            Ok(report)
        })
    }

    pub fn overnight_mirror_counts(&self, session_id: &str) -> GooseResult<OvernightMirrorCounts> {
        validate_required("session_id", session_id)?;
        self.ensure_overnight_mirror_tables()?;
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        let session_exists: bool = conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM overnight_sync_sessions WHERE session_id = ?1)",
            params![session_id],
            |row| row.get::<_, i64>(0),
        )? != 0;
        let raw_notification_count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM ble_raw_notifications WHERE session_id = ?1",
            params![session_id],
            |row| row.get(0),
        )?;
        let historical_range_poll_count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM historical_range_polls WHERE session_id = ?1",
            params![session_id],
            |row| row.get(0),
        )?;
        let successful_historical_range_poll_count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM historical_range_polls WHERE session_id = ?1 AND status = 'success'",
            params![session_id],
            |row| row.get(0),
        )?;
        Ok(OvernightMirrorCounts {
            schema: "goose.overnight-mirror-counts.v1".to_string(),
            session_id: session_id.to_string(),
            session_exists,
            raw_notification_count,
            historical_range_poll_count,
            successful_historical_range_poll_count,
        })
    }

    pub fn insert_raw_evidence(&self, input: RawEvidenceInput<'_>) -> GooseResult<bool> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        validate_required("evidence_id", input.evidence_id)?;
        validate_required("source", input.source)?;
        validate_required("captured_at", input.captured_at)?;
        validate_required("device_model", input.device_model)?;
        validate_required("sensitivity", input.sensitivity)?;
        if let Some(capture_session_id) = input.capture_session_id {
            validate_required("capture_session_id", capture_session_id)?;
        }

        let payload_hex = hex::encode(input.payload);
        let sha256 = sha256_hex(input.payload);

        let mut statement = conn.prepare_cached(
            r#"
            INSERT OR IGNORE INTO raw_evidence (
                evidence_id,
                source,
                captured_at,
                device_model,
                payload_hex,
                sha256,
                sensitivity,
                capture_session_id,
                device_uuid
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
            "#,
        )?;
        let changed = statement.execute(params![
            input.evidence_id,
            input.source,
            input.captured_at,
            input.device_model,
            payload_hex,
            sha256,
            input.sensitivity,
            input.capture_session_id,
            input.device_uuid
        ])?;
        if changed > 0 {
            return Ok(true);
        }

        let mut statement =
            conn.prepare_cached("SELECT sha256 FROM raw_evidence WHERE evidence_id = ?1")?;
        let existing_sha256: Option<String> = statement
            .query_row(params![input.evidence_id], |row| row.get(0))
            .optional()?;
        match existing_sha256 {
            Some(existing_sha256) if existing_sha256 == sha256 => Ok(false),
            Some(_) => Err(GooseError::message(format!(
                "raw evidence id {} already exists with a different checksum",
                input.evidence_id
            ))),
            None => Err(GooseError::message(format!(
                "raw evidence id {} insert was ignored but no existing row was found",
                input.evidence_id
            ))),
        }
    }

    pub fn insert_decoded_frame(&self, input: DecodedFrameInput<'_>) -> GooseResult<bool> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        validate_required("frame_id", input.frame_id)?;
        validate_required("evidence_id", input.evidence_id)?;
        validate_required("parser_version", input.parser_version)?;

        let parsed_payload_json = serde_json::to_string(&input.parsed.parsed_payload)
            .map_err(|error| GooseError::message(error.to_string()))?;
        let warnings_json = serde_json::to_string(&input.parsed.warnings)
            .map_err(|error| GooseError::message(error.to_string()))?;

        let mut statement = conn.prepare_cached(
            r#"
            INSERT OR IGNORE INTO decoded_frames (
                frame_id,
                evidence_id,
                device_type,
                raw_len,
                header_len,
                declared_len,
                payload_hex,
                payload_crc_hex,
                header_crc_valid,
                payload_crc_valid,
                packet_type,
                packet_type_name,
                sequence,
                command_or_event,
                parsed_payload_json,
                parser_version,
                warnings_json,
                device_uuid
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18)
            "#,
        )?;
        let changed = statement.execute(params![
            input.frame_id,
            input.evidence_id,
            device_type_name(input.parsed.device_type),
            input.parsed.raw_len as i64,
            input.parsed.header_len as i64,
            input.parsed.declared_len as i64,
            input.parsed.payload_hex,
            input.parsed.payload_crc_hex,
            bool_to_i64(input.parsed.header_crc_valid),
            bool_to_i64(input.parsed.payload_crc_valid),
            input.parsed.packet_type.map(i64::from),
            input.parsed.packet_type_name,
            input.parsed.sequence.map(i64::from),
            input.parsed.command_or_event.map(i64::from),
            parsed_payload_json,
            input.parser_version,
            warnings_json,
            input.device_uuid
        ])?;
        Ok(changed > 0)
    }

    pub fn start_capture_session(&self, input: CaptureSessionInput<'_>) -> GooseResult<bool> {
        validate_required("session_id", input.session_id)?;
        validate_required("source", input.source)?;
        validate_required("device_model", input.device_model)?;
        validate_json_object("provenance_json", input.provenance_json)?;
        validate_non_negative("started_at_unix_ms", input.started_at_unix_ms)?;

        if let Some(existing) = self.capture_session(input.session_id)? {
            let expected = CaptureSessionRow {
                session_id: input.session_id.to_string(),
                source: input.source.to_string(),
                started_at_unix_ms: input.started_at_unix_ms,
                ended_at_unix_ms: None,
                device_model: input.device_model.to_string(),
                active_device_id: input.active_device_id.map(str::to_string),
                status: "active".to_string(),
                frame_count: 0,
                provenance_json: input.provenance_json.to_string(),
            };
            if existing == expected {
                return Ok(false);
            }
            return Err(GooseError::message(format!(
                "capture session {} already exists with different metadata",
                input.session_id
            )));
        }

        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        let changed = conn.execute(
            r#"
            INSERT INTO capture_sessions (
                session_id,
                source,
                started_at_unix_ms,
                ended_at_unix_ms,
                device_model,
                active_device_id,
                status,
                frame_count,
                provenance_json
            ) VALUES (?1, ?2, ?3, NULL, ?4, ?5, 'active', 0, ?6)
            "#,
            params![
                input.session_id,
                input.source,
                input.started_at_unix_ms,
                input.device_model,
                input.active_device_id,
                input.provenance_json,
            ],
        )?;
        Ok(changed > 0)
    }

    /// Writes `active_device_id` to a capture session that currently has a NULL device id.
    /// If the session already has an `active_device_id` the row is not modified (idempotent).
    /// Returns `true` when the row was updated, `false` when it was already set or not found.
    pub fn set_capture_session_device_id(
        &self,
        session_id: &str,
        active_device_id: &str,
    ) -> GooseResult<bool> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        validate_required("session_id", session_id)?;
        validate_required("active_device_id", active_device_id)?;
        let changed = conn.execute(
            r#"
            UPDATE capture_sessions
            SET active_device_id = ?2
            WHERE session_id = ?1
              AND active_device_id IS NULL
            "#,
            params![session_id, active_device_id],
        )?;
        Ok(changed > 0)
    }

    pub fn finish_capture_session(
        &self,
        session_id: &str,
        ended_at_unix_ms: i64,
        frame_count: i64,
    ) -> GooseResult<CaptureSessionRow> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        validate_required("session_id", session_id)?;
        validate_non_negative("ended_at_unix_ms", ended_at_unix_ms)?;
        validate_non_negative("frame_count", frame_count)?;
        let Some(existing) = self.capture_session(session_id)? else {
            return Err(GooseError::message(format!(
                "capture session {session_id} not found"
            )));
        };
        if ended_at_unix_ms < existing.started_at_unix_ms {
            return Err(GooseError::message(
                "ended_at_unix_ms must be greater than or equal to started_at_unix_ms",
            ));
        }

        conn.execute(
            r#"
            UPDATE capture_sessions
            SET ended_at_unix_ms = ?2,
                status = 'finished',
                frame_count = ?3,
                updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
            WHERE session_id = ?1
            "#,
            params![session_id, ended_at_unix_ms, frame_count],
        )?;
        self.capture_session(session_id)?
            .ok_or_else(|| GooseError::message(format!("capture session {session_id} not found")))
    }

    pub fn capture_session(&self, session_id: &str) -> GooseResult<Option<CaptureSessionRow>> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        validate_required("session_id", session_id)?;
        conn.query_row(
            r#"
                SELECT
                    session_id,
                    source,
                    started_at_unix_ms,
                    ended_at_unix_ms,
                    device_model,
                    active_device_id,
                    status,
                    frame_count,
                    provenance_json
                FROM capture_sessions
                WHERE session_id = ?1
                "#,
            params![session_id],
            capture_session_from_row,
        )
        .optional()
        .map_err(GooseError::from)
    }

    pub fn capture_sessions_between(
        &self,
        start_unix_ms: i64,
        end_unix_ms: i64,
    ) -> GooseResult<Vec<CaptureSessionRow>> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        validate_non_negative("start_unix_ms", start_unix_ms)?;
        validate_non_negative("end_unix_ms", end_unix_ms)?;
        if end_unix_ms < start_unix_ms {
            return Err(GooseError::message(
                "end_unix_ms must be greater than or equal to start_unix_ms",
            ));
        }
        let mut statement = conn.prepare(
            r#"
            SELECT
                session_id,
                source,
                started_at_unix_ms,
                ended_at_unix_ms,
                device_model,
                active_device_id,
                status,
                frame_count,
                provenance_json
            FROM capture_sessions
            WHERE started_at_unix_ms < ?2
              AND COALESCE(ended_at_unix_ms, started_at_unix_ms) >= ?1
            ORDER BY started_at_unix_ms, session_id
            "#,
        )?;
        let rows = statement.query_map(
            params![start_unix_ms, end_unix_ms],
            capture_session_from_row,
        )?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(GooseError::from)
    }

    pub fn insert_step_counter_sample(
        &self,
        input: StepCounterSampleInput<'_>,
    ) -> GooseResult<bool> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        validate_step_counter_sample_input(&input)?;
        if let Some(existing) = self.step_counter_sample(input.sample_id)? {
            let same = existing.sample_time_unix_ms == input.sample_time_unix_ms
                && existing.counter_value == input.counter_value
                && existing.cadence_spm == input.cadence_spm
                && existing.activity_state.as_deref() == input.activity_state
                && existing.source_kind == input.source_kind
                && existing.packet_family == input.packet_family
                && existing.json_path == input.json_path
                && existing.frame_id.as_deref() == input.frame_id
                && existing.evidence_id.as_deref() == input.evidence_id
                && existing.capture_session_id.as_deref() == input.capture_session_id
                && existing.quality_flags_json == input.quality_flags_json
                && existing.provenance_json == input.provenance_json;
            if same {
                return Ok(false);
            }
            return Err(GooseError::message(format!(
                "step counter sample {} already exists with different metadata",
                input.sample_id
            )));
        }

        let changed = conn.execute(
            r#"
            INSERT INTO step_counter_samples (
                sample_id,
                sample_time_unix_ms,
                counter_value,
                cadence_spm,
                activity_state,
                source_kind,
                packet_family,
                json_path,
                frame_id,
                evidence_id,
                capture_session_id,
                quality_flags_json,
                provenance_json
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
            "#,
            params![
                input.sample_id,
                input.sample_time_unix_ms,
                input.counter_value,
                input.cadence_spm,
                input.activity_state,
                input.source_kind,
                input.packet_family,
                input.json_path,
                input.frame_id,
                input.evidence_id,
                input.capture_session_id,
                input.quality_flags_json,
                input.provenance_json,
            ],
        )?;
        Ok(changed > 0)
    }

    pub fn step_counter_sample(
        &self,
        sample_id: &str,
    ) -> GooseResult<Option<StepCounterSampleRow>> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        validate_required("sample_id", sample_id)?;
        conn.query_row(
            r#"
                SELECT
                    sample_id,
                    sample_time_unix_ms,
                    counter_value,
                    cadence_spm,
                    activity_state,
                    source_kind,
                    packet_family,
                    json_path,
                    frame_id,
                    evidence_id,
                    capture_session_id,
                    quality_flags_json,
                    provenance_json,
                    created_at
                FROM step_counter_samples
                WHERE sample_id = ?1
                "#,
            params![sample_id],
            step_counter_sample_from_row,
        )
        .optional()
        .map_err(GooseError::from)
    }

    pub fn step_counter_samples_between(
        &self,
        start_time_unix_ms: i64,
        end_time_unix_ms: i64,
    ) -> GooseResult<Vec<StepCounterSampleRow>> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        validate_non_negative("start_time_unix_ms", start_time_unix_ms)?;
        validate_non_negative("end_time_unix_ms", end_time_unix_ms)?;
        validate_window_order(start_time_unix_ms, end_time_unix_ms)?;
        let mut statement = conn.prepare(
            r#"
            SELECT
                    sample_id,
                    sample_time_unix_ms,
                    counter_value,
                    cadence_spm,
                    activity_state,
                    source_kind,
                    packet_family,
                json_path,
                frame_id,
                evidence_id,
                capture_session_id,
                quality_flags_json,
                provenance_json,
                created_at
            FROM step_counter_samples
            WHERE sample_time_unix_ms >= ?1
              AND sample_time_unix_ms < ?2
            ORDER BY sample_time_unix_ms, sample_id
            "#,
        )?;
        let rows = statement.query_map(
            params![start_time_unix_ms, end_time_unix_ms],
            step_counter_sample_from_row,
        )?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(GooseError::from)
    }

    pub fn raw_evidence(&self, evidence_id: &str) -> GooseResult<Option<RawEvidenceRow>> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        conn.query_row(
            r#"
                SELECT
                    evidence_id,
                    source,
                    captured_at,
                    device_model,
                    payload_hex,
                    sha256,
                    sensitivity,
                    capture_session_id,
                    device_uuid
                FROM raw_evidence
                WHERE evidence_id = ?1
                "#,
            params![evidence_id],
            |row| {
                Ok(RawEvidenceRow {
                    evidence_id: row.get(0)?,
                    source: row.get(1)?,
                    captured_at: row.get(2)?,
                    device_model: row.get(3)?,
                    payload_hex: row.get(4)?,
                    sha256: row.get(5)?,
                    sensitivity: row.get(6)?,
                    capture_session_id: row.get(7)?,
                    device_uuid: row.get(8)?,
                })
            },
        )
        .optional()
        .map_err(GooseError::from)
    }

    pub fn raw_evidence_between(&self, start: &str, end: &str) -> GooseResult<Vec<RawEvidenceRow>> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        validate_required("start", start)?;
        validate_required("end", end)?;

        let mut statement = conn.prepare(
            r#"
            SELECT
                evidence_id,
                source,
                captured_at,
                device_model,
                payload_hex,
                sha256,
                sensitivity,
                capture_session_id,
                device_uuid
            FROM raw_evidence
            WHERE captured_at >= ?1 AND captured_at < ?2
            ORDER BY captured_at, evidence_id
            "#,
        )?;
        let rows = statement.query_map(params![start, end], |row| {
            Ok(RawEvidenceRow {
                evidence_id: row.get(0)?,
                source: row.get(1)?,
                captured_at: row.get(2)?,
                device_model: row.get(3)?,
                payload_hex: row.get(4)?,
                sha256: row.get(5)?,
                sensitivity: row.get(6)?,
                capture_session_id: row.get(7)?,
                device_uuid: row.get(8)?,
            })
        })?;

        rows.collect::<Result<Vec<_>, _>>()
            .map_err(GooseError::from)
    }

    pub fn raw_evidence_payload_bytes(&self) -> GooseResult<i64> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        Self::raw_evidence_payload_bytes_with_conn(&conn)
    }

    fn raw_evidence_payload_bytes_with_conn(conn: &Connection) -> GooseResult<i64> {
        Ok(conn.query_row(
            r#"
            SELECT COALESCE(SUM(LENGTH(payload_hex) / 2), 0)
            FROM raw_evidence
            WHERE payload_hex != ''
            "#,
            [],
            |row| row.get(0),
        )?)
    }

    pub fn compact_raw_evidence_payloads_to_limit(
        &self,
        limit_bytes: i64,
    ) -> GooseResult<RawEvidencePayloadRetentionReport> {
        validate_non_negative("limit_bytes", limit_bytes)?;
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        let before_bytes = Self::raw_evidence_payload_bytes_with_conn(&conn)?;
        if before_bytes <= limit_bytes {
            return Ok(RawEvidencePayloadRetentionReport {
                limit_bytes,
                before_bytes,
                after_bytes: before_bytes,
                compacted_rows: 0,
                freed_bytes: 0,
            });
        }

        let mut bytes_to_free = before_bytes - limit_bytes;
        let compacted_ids = {
            let mut statement = conn.prepare(
                r#"
                SELECT evidence_id, LENGTH(payload_hex) / 2
                FROM raw_evidence
                WHERE payload_hex != ''
                ORDER BY captured_at, evidence_id
                "#,
            )?;
            let rows = statement.query_map([], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
            })?;

            let mut compacted_ids = Vec::new();
            for row in rows {
                let (evidence_id, payload_bytes) = row?;
                if bytes_to_free <= 0 {
                    break;
                }
                bytes_to_free -= payload_bytes;
                compacted_ids.push(evidence_id);
            }
            compacted_ids
        };

        let mut compacted_rows = 0;
        for evidence_id in compacted_ids {
            compacted_rows += conn.execute(
                "UPDATE raw_evidence SET payload_hex = '' WHERE evidence_id = ?1",
                params![evidence_id],
            )? as i64;
        }

        let after_bytes = Self::raw_evidence_payload_bytes_with_conn(&conn)?;
        Ok(RawEvidencePayloadRetentionReport {
            limit_bytes,
            before_bytes,
            after_bytes,
            compacted_rows,
            freed_bytes: before_bytes - after_bytes,
        })
    }

    pub fn decoded_frames_between(
        &self,
        start: &str,
        end: &str,
    ) -> GooseResult<Vec<DecodedFrameRow>> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        validate_required("start", start)?;
        validate_required("end", end)?;

        let mut statement = conn.prepare(
            r#"
            SELECT
                decoded_frames.frame_id,
                decoded_frames.evidence_id,
                raw_evidence.captured_at,
                decoded_frames.device_type,
                decoded_frames.raw_len,
                decoded_frames.header_len,
                decoded_frames.declared_len,
                decoded_frames.payload_hex,
                decoded_frames.payload_crc_hex,
                decoded_frames.header_crc_valid,
                decoded_frames.payload_crc_valid,
                decoded_frames.packet_type,
                decoded_frames.packet_type_name,
                decoded_frames.sequence,
                decoded_frames.command_or_event,
                decoded_frames.parsed_payload_json,
                decoded_frames.parser_version,
                decoded_frames.warnings_json,
                decoded_frames.device_uuid
            FROM decoded_frames
            INNER JOIN raw_evidence
                ON raw_evidence.evidence_id = decoded_frames.evidence_id
            WHERE raw_evidence.captured_at >= ?1 AND raw_evidence.captured_at < ?2
            ORDER BY raw_evidence.captured_at, decoded_frames.frame_id
            "#,
        )?;
        let rows = statement.query_map(params![start, end], decoded_frame_from_row)?;

        rows.collect::<Result<Vec<_>, _>>()
            .map_err(GooseError::from)
    }

    pub fn decoded_frame(&self, frame_id: &str) -> GooseResult<Option<DecodedFrameRow>> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        validate_required("frame_id", frame_id)?;
        conn.query_row(
            r#"
                SELECT
                    decoded_frames.frame_id,
                    decoded_frames.evidence_id,
                    raw_evidence.captured_at,
                    decoded_frames.device_type,
                    decoded_frames.raw_len,
                    decoded_frames.header_len,
                    decoded_frames.declared_len,
                    decoded_frames.payload_hex,
                    decoded_frames.payload_crc_hex,
                    decoded_frames.header_crc_valid,
                    decoded_frames.payload_crc_valid,
                    decoded_frames.packet_type,
                    decoded_frames.packet_type_name,
                    decoded_frames.sequence,
                    decoded_frames.command_or_event,
                    decoded_frames.parsed_payload_json,
                    decoded_frames.parser_version,
                    decoded_frames.warnings_json,
                    decoded_frames.device_uuid
                FROM decoded_frames
                INNER JOIN raw_evidence
                    ON raw_evidence.evidence_id = decoded_frames.evidence_id
                WHERE decoded_frames.frame_id = ?1
                "#,
            params![frame_id],
            decoded_frame_from_row,
        )
        .optional()
        .map_err(GooseError::from)
    }

    pub fn upsert_upload_cursor(
        &self,
        namespace: &str,
        stream: &str,
        value: &str,
    ) -> GooseResult<()> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        conn.execute(
            "INSERT OR REPLACE INTO upload_cursors (namespace, stream, value) VALUES (?1, ?2, ?3)",
            params![namespace, stream, value],
        )?;
        Ok(())
    }

    pub fn get_upload_cursor(&self, namespace: &str, stream: &str) -> GooseResult<Option<String>> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        conn.query_row(
            "SELECT value FROM upload_cursors WHERE namespace=?1 AND stream=?2",
            params![namespace, stream],
            |row| row.get(0),
        )
        .optional()
        .map_err(GooseError::from)
    }

    /// Mark specific rows in a stream table as synced=1 by rowid.
    /// The stream name must be in STREAM_ALLOWLIST to prevent SQL injection via table name
    /// interpolation (T-29-03 mitigation). row_ids are fully parameterised.
    pub fn mark_synced_rows(&self, stream: &str, row_ids: &[i64]) -> GooseResult<usize> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        if !STREAM_ALLOWLIST.contains(&stream) {
            return Err(GooseError::message(format!("unknown stream: {stream}")));
        }
        if row_ids.is_empty() {
            return Ok(0);
        }
        let placeholders = (1..=row_ids.len())
            .map(|i| format!("?{i}"))
            .collect::<Vec<_>>()
            .join(",");
        let sql = format!("UPDATE {stream} SET synced=1 WHERE rowid IN ({placeholders})");
        let count = conn.execute(&sql, params_from_iter(row_ids.iter()))?;
        Ok(count)
    }

    /// Return up to `limit` rows from a stream table where synced=0, ordered by ts.
    /// Each row is returned as a JSON object including the "rowid" key so callers can
    /// pass rowids back to mark_synced_rows.
    /// The stream name must be in STREAM_ALLOWLIST.
    pub fn rows_pending_upload(
        &self,
        stream: &str,
        limit: i64,
    ) -> GooseResult<Vec<serde_json::Value>> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        if !STREAM_ALLOWLIST.contains(&stream) {
            return Err(GooseError::message(format!("unknown stream: {stream}")));
        }
        if limit <= 0 {
            return Err(GooseError::message("limit must be a positive integer"));
        }
        let sql = format!("SELECT rowid, * FROM {stream} WHERE synced=0 ORDER BY ts LIMIT ?1");
        let mut statement = conn.prepare(&sql)?;
        let col_names: Vec<String> = statement
            .column_names()
            .into_iter()
            .map(String::from)
            .collect();
        let rows = statement.query_map(params![limit], |row| {
            let mut obj = serde_json::Map::new();
            for (i, name) in col_names.iter().enumerate() {
                let val = match row.get_ref(i)? {
                    rusqlite::types::ValueRef::Null => serde_json::Value::Null,
                    rusqlite::types::ValueRef::Integer(v) => serde_json::Value::Number(v.into()),
                    rusqlite::types::ValueRef::Real(v) => serde_json::Value::Number(
                        serde_json::Number::from_f64(v)
                            .unwrap_or_else(|| serde_json::Number::from(0)),
                    ),
                    rusqlite::types::ValueRef::Text(v) => {
                        serde_json::Value::String(std::str::from_utf8(v).unwrap_or("").to_string())
                    }
                    rusqlite::types::ValueRef::Blob(_) => serde_json::Value::Null,
                };
                obj.insert(name.clone(), val);
            }
            Ok(serde_json::Value::Object(obj))
        })?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(GooseError::from)
    }

    /// Populate hr_samples and rr_intervals from decoded_frames within the given time window.
    /// Uses INSERT OR IGNORE to be idempotent (UNIQUE(device_id, ts) prevents duplicates).
    /// Backfilled rows have synced=0 (the default) so they appear in rows_pending_upload
    /// without being stranded by any highwater cursor — rows_pending_upload uses WHERE synced=0,
    /// not ts > highwater.
    /// All inserts are wrapped in a single immediate_transaction for atomicity.
    pub fn backfill_streams_from_decoded_frames(
        &self,
        device_id: &str,
        start_ts: f64,
        end_ts: f64,
    ) -> GooseResult<BackfillReport> {
        let start_iso = unix_f64_to_iso8601(start_ts);
        let end_iso = unix_f64_to_iso8601(end_ts);
        let frames = self.decoded_frames_between(&start_iso, &end_iso)?;

        let mut hr_rows: Vec<(f64, i64)> = Vec::new();
        let mut rr_rows: Vec<(f64, i64)> = Vec::new();

        for frame in &frames {
            if !frame.header_crc_valid || !frame.payload_crc_valid {
                continue;
            }
            let parsed: Option<ParsedPayload> =
                serde_json::from_str(&frame.parsed_payload_json).unwrap_or(None);
            let Some(ParsedPayload::DataPacket {
                timestamp_seconds,
                body_summary,
                ..
            }) = parsed
            else {
                continue;
            };
            let ts_unix: Option<f64> = timestamp_seconds.map(|s| s as f64);
            let Some(ref summary) = body_summary else {
                continue;
            };
            match summary {
                DataPacketBodySummary::NormalHistory {
                    hr_present,
                    marker_value,
                    ..
                } => {
                    if hr_present.unwrap_or(false)
                        && let (Some(ts), Some(bpm)) = (ts_unix, marker_value)
                    {
                        hr_rows.push((ts, *bpm as i64));
                    }
                }
                DataPacketBodySummary::RawMotionK10 { heart_rate, .. } => {
                    if let (Some(ts), Some(bpm)) = (ts_unix, heart_rate) {
                        hr_rows.push((ts, *bpm as i64));
                    }
                }
                DataPacketBodySummary::V24History {
                    hr: v24_hr,
                    rr_intervals_ms,
                    skin_contact,
                    ..
                } => {
                    let contact = skin_contact.unwrap_or(0) == 1;
                    if contact && let (Some(ts), Some(bpm)) = (ts_unix, *v24_hr) {
                        hr_rows.push((ts, bpm as i64));
                    }
                    if let Some(ts_base) = ts_unix {
                        let mut t = ts_base;
                        for &ms in rr_intervals_ms.iter() {
                            rr_rows.push((t, ms as i64));
                            t += ms as f64 / 1000.0;
                        }
                    }
                }
                _ => {}
            }
        }

        let hr_to_insert = hr_rows.clone();
        let rr_to_insert = rr_rows.clone();
        let device_id_owned = device_id.to_string();

        self.immediate_transaction(|conn| {
            let mut hr_inserted = 0usize;
            for (ts, bpm) in &hr_to_insert {
                hr_inserted += conn.execute(
                    "INSERT OR IGNORE INTO hr_samples (device_id, ts, bpm) VALUES (?1, ?2, ?3)",
                    params![device_id_owned, ts, bpm],
                )?;
            }
            let mut rr_inserted = 0usize;
            for (ts, interval_ms) in &rr_to_insert {
                rr_inserted += conn.execute(
                    "INSERT OR IGNORE INTO rr_intervals (device_id, ts, interval_ms) VALUES (?1, ?2, ?3)",
                    params![device_id_owned, ts, interval_ms],
                )?;
            }
            Ok(BackfillReport {
                hr_inserted,
                rr_inserted,
                events_inserted: 0,
                battery_inserted: 0,
            })
        })
    }

    /// Return all rr_intervals rows with ts in [start_ts, end_ts).
    pub fn rr_intervals_between(
        &self,
        start_ts: f64,
        end_ts: f64,
    ) -> GooseResult<Vec<RrIntervalRow>> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        let mut stmt = conn.prepare(
            "SELECT device_id, ts, interval_ms, synced FROM rr_intervals \
             WHERE ts >= ?1 AND ts < ?2 ORDER BY ts",
        )?;
        let rows = stmt
            .query_map(params![start_ts, end_ts], |row| {
                Ok(RrIntervalRow {
                    device_id: row.get(0)?,
                    ts: row.get(1)?,
                    interval_ms: row.get(2)?,
                    synced: row.get(3)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(rows)
    }

    /// Delete synced rows (synced=1) older than older_than_ts from a stream table.
    /// Stream table pruning only removes rows with synced=1 — unsynced rows (synced=0)
    /// are structurally protected regardless of age. Same allowlist as mark_synced_rows.
    ///
    /// Stream table pruning (DELETE FROM {stream} WHERE synced=1 AND ...) is intentionally
    /// NOT performed in compact_raw_evidence_payloads_to_limit — the invariant is enforced
    /// at the call site by the upload pipeline which checks synced=1 before any stream
    /// table DELETE.
    pub fn prune_synced_stream_rows(&self, stream: &str, older_than_ts: f64) -> GooseResult<usize> {
        let conn = self
            .conn
            .lock()
            .map_err(|_| GooseError::message("store mutex poisoned"))?;
        if !STREAM_ALLOWLIST.contains(&stream) {
            return Err(GooseError::message(format!("unknown stream: {stream}")));
        }
        let sql = format!("DELETE FROM {stream} WHERE synced=1 AND ts < ?1");
        let count = conn.execute(&sql, params![older_than_ts])?;
        Ok(count)
    }
}
