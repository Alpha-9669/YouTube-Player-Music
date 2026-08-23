#define freeExtension comment

"youtube_player_music" callExtension "debug|1";
"youtube_player_music" callExtension "playlistload|https://www.youtube.com/playlist?list=PLgULlLHTSGISMiG9fB3jIEOabgXOZNAB6";
"youtube_player_music" callExtension "playlistitem|1|0";
"youtube_player_music" callExtension "prefetch|https://www.youtube.com/watch?v=oh0RQ_TgDnQ&list=PLgULlLHTSGISMiG9fB3jIEOabgXOZNAB6";
sleep 3;
"youtube_player_music" callExtension "play|https://www.youtube.com/watch?v=oh0RQ_TgDnQ&list=PLgULlLHTSGISMiG9fB3jIEOabgXOZNAB6|70";
sleep 8;
"youtube_player_music" callExtension "status";
"youtube_player_music" callExtension "timeline";
"youtube_player_music" callExtension "stop";
sleep 1;
exit;
