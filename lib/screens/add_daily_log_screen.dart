import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import '../db/database_helper.dart';
import '../models/daily_log.dart';
import '../models/material_item.dart';
import '../services/image_compression_service.dart';

class AddDailyLogScreen extends StatefulWidget {
  final String siteId;
  final DailyLog? existingLog; // pass to edit instead of create
  const AddDailyLogScreen({super.key, required this.siteId, this.existingLog});

  @override
  State<AddDailyLogScreen> createState() => _AddDailyLogScreenState();
}

class _AddDailyLogScreenState extends State<AddDailyLogScreen> {
  late final _weatherController = TextEditingController(text: widget.existingLog?.weather);
  late final _crewController = TextEditingController(text: widget.existingLog?.crewCount?.toString());
  late final _workController = TextEditingController(text: widget.existingLog?.workCompleted);
  late final _issuesController = TextEditingController(text: widget.existingLog?.issues);
  late final List<String> _photoPaths = List.of(widget.existingLog?.photoPaths ?? []);

  // Generated up front (even for a brand-new log) so materials/equipment
  // rows always have a valid log_id to reference, whether the log is new
  // or being edited.
  late final String _logId = widget.existingLog?.id ?? const Uuid().v4();

  List<MaterialItem> _materials = [];
  bool _saving = false;
  bool _loadingMaterials = false;

  bool get _isEditing => widget.existingLog != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadMaterials();
    }
  }

  Future<void> _loadMaterials() async {
    setState(() => _loadingMaterials = true);
    final materials = await DatabaseHelper.instance.getMaterialsForLog(_logId);
    if (mounted) setState(() {
      _materials = materials;
      _loadingMaterials = false;
    });
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 90);
    if (file == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final fileName = '${const Uuid().v4()}${p.extension(file.path)}';
    final rawPath = p.join(appDir.path, 'photos', fileName);
    await Directory(p.join(appDir.path, 'photos')).create(recursive: true);

    // Compress before persisting the path, so exports and Drive backups
    // stay lean.
    final saved = await ImageCompressionService.compressAndSave(
      sourcePath: file.path,
      destinationPath: rawPath,
    );

    setState(() => _photoPaths.add(saved.path));
  }

  Future<Position?> _tryGetLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied) return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      return null; // GPS optional — don't block saving if unavailable
    }
  }

  Future<void> _addMaterialDialog() async {
    final nameController = TextEditingController();
    final qtyController = TextEditingController();
    final unitController = TextEditingController();
    MaterialCategory category = MaterialCategory.material;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Material / Equipment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Item name (e.g. Cement, Excavator)'),
                autofocus: true,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyController,
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: unitController,
                      decoration: const InputDecoration(labelText: 'Unit (bags, m3...)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<MaterialCategory>(
                value: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: MaterialCategory.values
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                    .toList(),
                onChanged: (v) => setDialogState(() => category = v ?? category),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      final qty = double.tryParse(qtyController.text.trim()) ?? 0;
      setState(() {
        _materials.add(MaterialItem(
          id: const Uuid().v4(),
          logId: _logId,
          itemName: nameController.text.trim(),
          quantity: qty,
          unit: unitController.text.trim().isEmpty ? null : unitController.text.trim(),
          category: category,
        ));
      });
    }
  }

  Future<void> _saveMaterials() async {
    // Simplest consistent strategy: replace all rows for this log with
    // whatever is currently in the in-memory list.
    await DatabaseHelper.instance.deleteMaterialsForLog(_logId);
    for (final item in _materials) {
      await DatabaseHelper.instance.insertMaterialItem(item);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    if (_isEditing) {
      final updated = DailyLog(
        id: _logId,
        siteId: widget.siteId,
        date: widget.existingLog!.date, // keep original date
        weather: _weatherController.text.trim().isEmpty ? null : _weatherController.text.trim(),
        crewCount: int.tryParse(_crewController.text.trim()),
        workCompleted: _workController.text.trim().isEmpty ? null : _workController.text.trim(),
        issues: _issuesController.text.trim().isEmpty ? null : _issuesController.text.trim(),
        photoPaths: _photoPaths,
        lat: widget.existingLog!.lat,
        lng: widget.existingLog!.lng,
        isSynced: false, // edited after last backup -> pending again
      );
      await DatabaseHelper.instance.updateDailyLog(updated);
    } else {
      final position = await _tryGetLocation();
      final log = DailyLog(
        id: _logId,
        siteId: widget.siteId,
        date: DateTime.now(),
        weather: _weatherController.text.trim().isEmpty ? null : _weatherController.text.trim(),
        crewCount: int.tryParse(_crewController.text.trim()),
        workCompleted: _workController.text.trim().isEmpty ? null : _workController.text.trim(),
        issues: _issuesController.text.trim().isEmpty ? null : _issuesController.text.trim(),
        photoPaths: _photoPaths,
        lat: position?.latitude,
        lng: position?.longitude,
        isSynced: false,
      );
      await DatabaseHelper.instance.insertDailyLog(log);
    }

    await _saveMaterials();

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Daily Log' : 'New Daily Log')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _weatherController, decoration: const InputDecoration(labelText: 'Weather')),
          const SizedBox(height: 12),
          TextField(
            controller: _crewController,
            decoration: const InputDecoration(labelText: 'Crew count'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _workController,
            decoration: const InputDecoration(labelText: 'Work completed'),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _issuesController,
            decoration: const InputDecoration(labelText: 'Issues / delays'),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickPhoto,
            icon: const Icon(Icons.camera_alt),
            label: Text('Add Photo (${_photoPaths.length})'),
          ),
          if (_photoPaths.isNotEmpty)
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _photoPaths.length,
                itemBuilder: (ctx, i) => Padding(
                  padding: const EdgeInsets.only(right: 8, top: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(_photoPaths[i]), width: 80, height: 80, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text('Materials & Equipment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              TextButton.icon(
                onPressed: _addMaterialDialog,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          if (_loadingMaterials) const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())),
          if (!_loadingMaterials && _materials.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text('No materials or equipment logged for this entry.', style: TextStyle(color: Colors.grey)),
            ),
          ..._materials.map((m) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  dense: true,
                  leading: Icon(m.category == MaterialCategory.equipment ? Icons.precision_manufacturing : Icons.inventory_2),
                  title: Text(m.itemName),
                  subtitle: Text('${m.quantity.toStringAsFixed(m.quantity == m.quantity.roundToDouble() ? 0 : 2)} ${m.unit ?? ''} • ${m.category.label}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _materials.remove(m)),
                  ),
                ),
              )),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CircularProgressIndicator()
                : Text(_isEditing ? 'Update Log' : 'Save Log'),
          ),
        ],
      ),
    );
  }
}
