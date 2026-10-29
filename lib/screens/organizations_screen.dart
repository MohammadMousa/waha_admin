import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/organization.dart';
import '../router/routes.dart';
import '../state/auth_state.dart';
import '../widgets/admin_sidebar.dart';
import '../widgets/framed_card.dart';

/// Landing screen for a super-admin with several organizations: pick one to
/// explore. The session then acts as that organization on every screen.
class OrganizationsScreen extends StatelessWidget {
  const OrganizationsScreen({super.key});

  void _explore(BuildContext context, Organization org) {
    context.read<AuthState>().selectOrganization(org);
    Navigator.of(context).pushReplacementNamed(Routes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthState>();
    final orgs = auth.organizations;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerLowest,
      body: Row(
        children: [
          const AdminSidebar(currentRoute: Routes.organizations),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Row(
                    children: [
                      Text('Organizations',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                        onPressed: () => context.read<AuthState>().refreshOrganizations(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: orgs.isEmpty
                      ? const Center(child: Text('No organizations found.'))
                      : CardGrid(
                          itemCount: orgs.length,
                          itemBuilder: (_, i) {
                            final o = orgs[i];
                            final current = auth.actingOrganization?.id == o.id;
                            return FramedCard(
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: scheme.primary.withValues(alpha: 0.15),
                                    child: Icon(Icons.apartment_outlined, color: scheme.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(o.name,
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                        Text(
                                            [if (o.slug != null) o.slug!, '#${o.id}'].join('  ·  '),
                                            style: TextStyle(fontSize: 12, color: scheme.outline)),
                                      ],
                                    ),
                                  ),
                                  current
                                      ? const Chip(label: Text('Current'))
                                      : FilledButton(
                                          onPressed: () => _explore(context, o),
                                          child: const Text('Explore'),
                                        ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
