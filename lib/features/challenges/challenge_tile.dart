import 'package:flutter/material.dart';
import '../tracking/tracking_models.dart';
import 'challenge_models.dart';
import 'challenge_page.dart';

String formatSeconds(num s) => formatDuration(Duration(seconds: s.round()));

class ChallengeTile extends StatelessWidget {
  final Challenge challenge;
  final VoidCallback onChanged;
  const ChallengeTile(
      {super.key, required this.challenge, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    final stats = [
      '${c.participants} ${c.participants == 1 ? 'participante' : 'participantes'}',
      if (c.avgSeconds != null) 'promedio ${formatSeconds(c.avgSeconds!)}',
    ].join(' · ');

    return ListTile(
      leading: CircleAvatar(child: Icon(c.type.icon)),
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${(c.distanceMeters / 1000).toStringAsFixed(2)} km · '
              '${c.isMine ? 'creado por ti' : c.creatorName}'),
          Text(stats),
          if (c.reason != null)
            Text(c.reason!,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.primary)),
        ],
      ),
      isThreeLine: true,
      trailing: c.myBestSeconds != null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber),
                Text('#${c.myPosition}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            )
          : null,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ChallengePage(challengeId: c.id)),
        );
        onChanged();
      },
    );
  }
}