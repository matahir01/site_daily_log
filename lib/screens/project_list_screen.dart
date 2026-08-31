import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/project.dart';
import 'project_dashboard_screen.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key});

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  List<Project> _projects = [];
  final _db = DatabaseHelper.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final projects = await _db.getProjects();
    setState(() => _projects = projects);
  }

  Future<void> _addProject() async {
    final nameController = TextEditingController();
    final clientController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Project'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Project name'),
              autofocus: true,
            ),
            TextField(
              controller: clientController,
              decoration: const InputDecoration(labelText: 'Client (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      final project = Project(
        id: const Uuid().v4(),
        name: nameController.text.trim(),
        client: clientController.text.trim().isEmpty ? null : clientController.text.trim(),
        createdAt: DateTime.now(),
      );
      await _db.insertProject(project);
      _load();
    }
  }

  Future<void> _confirmDeleteProject(Project p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: const Text('This deletes the project and all its sites, logs, and expenses. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteProject(p.id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Projects')),
      body: _projects.isEmpty
          ? const Center(child: Text('No projects yet. Tap + to add one.'))
          : ListView.builder(
              itemCount: _projects.length,
              itemBuilder: (ctx, i) {
                final p = _projects[i];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.construction)),
                  title: Text(p.name),
                  subtitle: p.client != null ? Text(p.client!) : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDeleteProject(p),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ProjectDashboardScreen(project: p)),
                  ).then((_) => _load()),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addProject,
        child: const Icon(Icons.add),
      ),
    );
  }
}
