import urllib.request
import json

url = 'https://api.github.com/repos/bengkelgadget-code/MUSIC_STREAM/actions/runs'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode('utf-8'))
    runs = data.get('workflow_runs', [])
    for r in runs[:3]:
        msg = r.get('head_commit', {}).get('message', '').split('\n')[0][:50]
        print("ID:", r['id'], "| Status:", r['status'], "| Conclusion:", r['conclusion'], "| Msg:", msg)
except Exception as e:
    print('Error:', e)
