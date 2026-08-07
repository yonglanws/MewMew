import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../state/app_state.dart';

const _uuid = Uuid();

/// 用户资料编辑页面（昵称 + 头像）
class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late final TextEditingController _name;
  late String _avatarPath;

  @override
  void initState() {
    super.initState();
    final p = context.read<AppState>().userProfile;
    _name = TextEditingController(text: p.name);
    _avatarPath = p.avatarPath;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (img == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final avatarsDir = Directory('${dir.path}/avatars');
    await avatarsDir.create(recursive: true);
    final dot = img.path.lastIndexOf('.');
    final ext = dot >= 0 ? img.path.substring(dot) : '.jpg';
    final saved =
        await File(img.path).copy('${avatarsDir.path}/${_uuid.v4()}$ext');
    if (!mounted) return;
    setState(() => _avatarPath = saved.path);
  }

  void _save() {
    final profile = UserProfile(
      name: _name.text.trim().isEmpty ? '我' : _name.text.trim(),
      avatarPath: _avatarPath,
    );
    context.read<AppState>().updateUserProfile(profile);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasAvatar =
        _avatarPath.isNotEmpty && File(_avatarPath).existsSync();
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的资料'),
        actions: [
          FilledButton.tonal(
            onPressed: _save,
            child: const Text('保存'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(
                children: [
                  hasAvatar
                      ? CircleAvatar(
                          radius: 56,
                          backgroundImage: FileImage(File(_avatarPath)),
                        )
                      : CircleAvatar(
                          radius: 56,
                          backgroundColor: cs.primaryContainer,
                          child: Icon(Icons.person,
                              size: 56, color: cs.onPrimaryContainer),
                        ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Material(
                      color: cs.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _pickAvatar,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.photo_camera_outlined,
                              size: 16, color: cs.onPrimary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '点击头像从相册选择图片',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '昵称',
              hintText: '请输入你的昵称',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
