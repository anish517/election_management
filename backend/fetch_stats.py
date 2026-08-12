import requests

login_resp = requests.post('http://localhost:8000/v1/auth/login/', json={'email_or_phone': 'admin@gmail.com', 'password': 'admin'})
token = login_resp.json().get('access')

if token:
    stats_resp = requests.get('http://localhost:8000/v1/organization/stats/', headers={'Authorization': f'Bearer {token}'})
    print(stats_resp.text)
else:
    print('Login failed:', login_resp.json())
