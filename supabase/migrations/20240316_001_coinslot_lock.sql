-- Coinslot Lock Mechanism Migration
-- This table tracks which device (MAC) currently has the coinslot locked
-- Lock is only released when modal is closed or specific actions are taken

CREATE TABLE IF NOT EXISTS coinslot_locks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    mac TEXT UNIQUE NOT NULL,
    locked_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
    session_token TEXT,
    created_at INTEGER DEFAULT (strftime('%s', 'now'))
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_coinslot_locks_mac ON coinslot_locks(mac);

-- Enable RLS (Row Level Security)
ALTER TABLE coinslot_locks ENABLE ROW LEVEL SECURITY;

-- Create policies for anon and authenticated roles
CREATE POLICY "Allow anon to read lock status" ON coinslot_locks
    FOR SELECT USING (true);

CREATE POLICY "Allow anon to insert new locks" ON coinslot_locks
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Allow anon to update own lock" ON coinslot_locks
    FOR UPDATE USING (mac = current_setting('app.current_mac', true));

CREATE POLICY "Allow anon to delete own lock" ON coinslot_locks
    FOR DELETE USING (mac = current_setting('app.current_mac', true));

-- Grant permissions
GRANT SELECT ON coinslot_locks TO anon;
GRANT INSERT ON coinslot_locks TO anon;
GRANT UPDATE ON coinslot_locks TO anon;
GRANT DELETE ON coinslot_locks TO anon;

GRANT SELECT ON coinslot_locks TO authenticated;
GRANT INSERT ON coinslot_locks TO authenticated;
GRANT UPDATE ON coinslot_locks TO authenticated;
GRANT DELETE ON coinslot_locks TO authenticated;