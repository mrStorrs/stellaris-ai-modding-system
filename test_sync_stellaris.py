"""Registration regressions using temporary descriptors and launcher databases."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('sync-stellaris-project-mods.sh')


class SyncTests(unittest.TestCase):
    def check_registration(self, legacy=False, discovered=False):
        with tempfile.TemporaryDirectory(prefix='cjs-sync-test-') as folder:
            root = Path(folder)
            projects = root/'projects'; project = projects/'exampleTweaks'
            project.mkdir(parents=True)
            state = root/'state'; descriptors = state/'mod'; descriptors.mkdir(parents=True)
            (project/'descriptor.mod').write_text('name="Example Tweaks"\nversion="1.0"\nsupported_version="v4.4.*"\ndependencies={ "Example Dependency" }\n')
            (descriptors/'dependency.mod').write_text('name="Example Dependency"\n')
            (descriptors/'unrelated.mod').write_text('name="Unrelated"\n')
            (state/'dlc_load.json').write_text(json.dumps({'enabled_mods': ['mod/dependency.mod', 'mod/unrelated.mod'], 'disabled_dlcs': ['untouched']}))
            db = sqlite3.connect(state/'launcher-v2.sqlite')
            db.executescript('''
                CREATE TABLE mods (id TEXT PRIMARY KEY, gameRegistryId TEXT, displayName TEXT,
                    version TEXT, tags TEXT, requiredVersion TEXT, dirPath TEXT, status TEXT,
                    source TEXT, timeUpdated INTEGER, isNew INTEGER, metadataStatus TEXT,
                    isMetadataApplied INTEGER, keepLatest INTEGER);
                CREATE TABLE playsets (id TEXT PRIMARY KEY, isActive INTEGER, updatedOn INTEGER);
                CREATE TABLE playsets_mods (playsetId TEXT, modId TEXT, enabled INTEGER, position INTEGER);
                INSERT INTO playsets VALUES ('active', 1, 0), ('other', 0, 0);
                INSERT INTO mods (id, gameRegistryId, displayName, source) VALUES
                    ('dependency', 'mod/dependency.mod', 'Example Dependency 4.4', 'steam'),
                    ('unrelated', 'mod/unrelated.mod', 'Unrelated', 'steam');
                INSERT INTO playsets_mods VALUES ('active', 'dependency', 1, 0), ('active', 'unrelated', 1, 1);
            ''')
            if legacy:
                db.execute('INSERT INTO mods (id, dirPath, displayName, source) VALUES (?, ?, ?, ?)',
                           ('legacy', str(project), 'Example Tweaks', 'local'))
                db.execute("INSERT INTO playsets_mods VALUES ('other', 'legacy', 0, 7)")
                db.execute("INSERT INTO playsets_mods VALUES ('active', 'legacy', 1, 2)")
            if discovered:
                db.execute('INSERT INTO mods (id, gameRegistryId, dirPath, displayName, source) VALUES (?, ?, ?, ?, ?)',
                           ('discovered', 'mod/exampleTweaks.mod', str(project), 'Example Tweaks', 'local'))
                db.execute("INSERT INTO playsets_mods VALUES ('active', 'discovered', 1, 3)")
            db.commit()
            env = dict(os.environ, SOURCE_ROOT=str(projects), STATE_ROOT=str(state), DEST_ROOT=str(descriptors), MOD_NAME='exampleTweaks', DRY_RUN='0')
            ids = []
            for _ in range(2):
                result = subprocess.run([str(SCRIPT)], env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                rows = db.execute('SELECT id, gameRegistryId, dirPath FROM mods WHERE source="local"').fetchall()
                self.assertEqual(len(rows), 1)
                ident, registry, directory = rows[0]; ids.append(ident)
                self.assertEqual((registry, directory), ('mod/exampleTweaks.mod', str(project)))
                enabled = [row[0] for row in db.execute('SELECT m.gameRegistryId FROM playsets_mods pm JOIN mods m ON m.id=pm.modId WHERE pm.playsetId="active" AND pm.enabled=1 ORDER BY pm.position')]
                self.assertEqual(enabled, ['mod/dependency.mod', 'mod/exampleTweaks.mod', 'mod/unrelated.mod'])
                load = json.loads((state/'dlc_load.json').read_text())
                self.assertEqual(load['enabled_mods'], enabled)
                self.assertEqual(load['disabled_dlcs'], ['untouched'])
                self.assertIn(f'path="{project}"', (descriptors/'exampleTweaks.mod').read_text())
                self.assertEqual(db.execute('SELECT displayName FROM mods WHERE id="dependency"').fetchone()[0], 'Example Dependency 4.4')
                if legacy:
                    self.assertEqual(db.execute('SELECT modId, enabled, position FROM playsets_mods WHERE playsetId="other"').fetchall(), [(ident, 0, 7)])
            self.assertEqual(ids[0], ids[1])
            if discovered: self.assertEqual(ids[0], 'discovered')
            elif legacy: self.assertEqual(ids[0], 'legacy')
            db.close()

    def test_fresh_registration_with_renamed_dependency(self):
        self.check_registration()

    def test_legacy_registration_with_renamed_dependency(self):
        self.check_registration(legacy=True)

    def test_discovered_duplicate_keeps_id_and_other_membership(self):
        self.check_registration(legacy=True, discovered=True)


if __name__ == '__main__':
    unittest.main()
