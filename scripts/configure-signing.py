"""Configure a CI-only project from Apple signing values, without printing secrets."""
import os
from pathlib import Path
import plistlib

get = os.environ.__getitem__
app_id, group_id, team = get('APP_BUNDLE_ID'), get('APP_GROUP_ID'), get('APPLE_TEAM_ID')
app_profile, widget_profile = get('APP_PROFILE_UUID'), get('WIDGET_PROFILE_UUID')
project = Path('project.yml')
spec = project.read_text()
spec = spec.replace('ru.roshfort.UrFUSchedule.ScheduleWidget', app_id + '.ScheduleWidget')
spec = spec.replace('ru.roshfort.UrFUSchedule', app_id)
spec = spec.replace('group.ru.roshfort.urfu.schedule', group_id)
spec = spec.replace('DEVELOPMENT_TEAM: ""', f'DEVELOPMENT_TEAM: "{team}"')
spec = spec.replace('PRODUCT_BUNDLE_IDENTIFIER: ' + app_id + '\n',
                    'PRODUCT_BUNDLE_IDENTIFIER: ' + app_id + '\n        CODE_SIGN_STYLE: Manual\n        CODE_SIGN_IDENTITY: Apple Distribution\n        PROVISIONING_PROFILE_SPECIFIER: ' + app_profile + '\n')
spec = spec.replace('PRODUCT_BUNDLE_IDENTIFIER: ' + app_id + '.ScheduleWidget\n',
                    'PRODUCT_BUNDLE_IDENTIFIER: ' + app_id + '.ScheduleWidget\n        CODE_SIGN_STYLE: Manual\n        CODE_SIGN_IDENTITY: Apple Distribution\n        PROVISIONING_PROFILE_SPECIFIER: ' + widget_profile + '\n')
project.write_text(spec)
store = Path('Shared/ScheduleStore.swift')
store.write_text(store.read_text().replace('group.ru.roshfort.urfu.schedule', group_id))
options = {'method': 'ad-hoc', 'signingStyle': 'manual', 'teamID': team,
           'provisioningProfiles': {app_id: app_profile, app_id + '.ScheduleWidget': widget_profile}}
with open(Path(get('RUNNER_TEMP')) / 'ExportOptions.plist', 'wb') as output:
    plistlib.dump(options, output)
