```
> cloudflared tunnel login
```

Tunnel should be created with CLI to have local configuration enabled (reading from configmap) Get the tunnel id with

```
> cloudflared tunnel list
```

Decode the token and fill the template secrets, the token will have the format of { s: string, t: string, a: string } which correspond to s = secret, t = tunnel id and a = account id

```
> cloudflared tunnel token <TUNNEL_ID> | base64 -d
```
