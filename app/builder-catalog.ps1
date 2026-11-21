# These are public HTTPS endpoints, not game authentication/matchmaking/UDP tests.
$BuilderCatalog=[ordered]@{
    youtube=@{Label='YouTube';Category='Основные';Domains=@('youtube.com','youtu.be','youtube-nocookie.com','youtubei.googleapis.com','youtube.googleapis.com','googlevideo.com','ytimg.com','ggpht.com','yt3.googleusercontent.com');Urls=@('https://www.youtube.com/','https://i.ytimg.com/vi/aqz-KE-bpKQ/hqdefault.jpg')}
    spotify=@{Label='Spotify';Category='Основные';Domains=@('spotify.com','scdn.co','spotifycdn.com');Urls=@('https://open.spotify.com/','https://accounts.spotify.com/')}
    discord=@{Label='Discord (сайт)';Category='Основные';Domains=@('discord.com','discord.gg','discordapp.com','discordapp.net','discord.media','discordcdn.com');Urls=@('https://discord.com/')}
    github=@{Label='GitHub';Category='Основные';Domains=@('github.com','githubusercontent.com','githubassets.com');Urls=@('https://github.com/','https://api.github.com/')}
    cloudflare=@{Label='Cloudflare';Category='Основные';Domains=@('cloudflare.com','cloudflare-dns.com','cdnjs.cloudflare.com');Urls=@('https://www.cloudflare.com/','https://cdnjs.cloudflare.com/')}
    google=@{Label='Google';Category='Основные';Domains=@('google.com','google.ru','gstatic.com','googleapis.com');Urls=@('https://www.google.com/','https://www.gstatic.com/generate_204')}
    twitch=@{Label='Twitch';Category='Основные';Domains=@('twitch.tv','ttvnw.net','jtvnw.net');Urls=@('https://www.twitch.tv/')}
    reddit=@{Label='Reddit';Category='Основные';Domains=@('reddit.com','redd.it');Urls=@('https://www.reddit.com/')}
    microsoft=@{Label='Microsoft / Xbox';Category='Основные';Domains=@('microsoft.com','live.com','xbox.com','xboxlive.com');Urls=@('https://www.microsoft.com/','https://www.xbox.com/')}
    chatgpt=@{Label='ChatGPT';Category='AI';Domains=@('chatgpt.com','openai.com','oaistatic.com','oaiusercontent.com');Urls=@('https://chatgpt.com/')}
    claude=@{Label='Claude';Category='AI';Domains=@('claude.ai','anthropic.com');Urls=@('https://claude.ai/')}
    steam=@{Label='Steam';Category='Игровые платформы';Domains=@('steampowered.com','steamcommunity.com','steamstatic.com','steamcontent.com');Urls=@('https://store.steampowered.com/','https://steamcommunity.com/')}
    battle_net=@{Label='Battle.net / Blizzard';Category='Игровые платформы';Domains=@('battle.net','blizzard.com','blzstatic.com');Urls=@('https://www.blizzard.com/','https://account.battle.net/')}
    ubisoft=@{Label='Ubisoft Connect';Category='Игровые платформы';Domains=@('ubisoft.com','ubisoftconnect.com','ubi.com');Urls=@('https://www.ubisoft.com/','https://ubisoftconnect.com/')}
    ea=@{Label='EA / Origin / Apex (сайт)';Category='Игровые платформы';Domains=@('ea.com','origin.com','respawn.com','apexlegends.com');Urls=@('https://www.ea.com/games/apex-legends')}
    pubg=@{Label='PUBG (сайт)';Category='Игровые платформы';Domains=@('pubg.com','krafton.com');Urls=@('https://www.pubg.com/')}
    warzone=@{Label='Warzone / Activision (сайт)';Category='Игровые платформы';Domains=@('callofduty.com','activision.com','demonware.net');Urls=@('https://www.callofduty.com/warzone')}
}
