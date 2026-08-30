import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/api_exception.dart';
import '../../../models/user.dart';
import '../../../widgets/user_avatar.dart';
import '../../auth/presentation/session_controller.dart';
import 'avatar_upload_controller.dart';
import 'edit_profile_controller.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, required this.user});

  final User user;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _usernameController = TextEditingController(
    text: widget.user.username,
  );
  late final _bioController = TextEditingController(
    text: widget.user.bio ?? '',
  );

  @override
  void dispose() {
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref
        .read(editProfileControllerProvider.notifier)
        .submit(
          username: _usernameController.text.trim(),
          bio: _bioController.text.trim(),
        );
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;

    ref.read(avatarUploadControllerProvider.notifier).upload(picked.path);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(editProfileControllerProvider);
    final error = state.hasError ? state.error : null;
    final apiError = error is ApiException ? error : null;

    final avatarState = ref.watch(avatarUploadControllerProvider);
    final avatarError = avatarState.hasError ? avatarState.error : null;
    final avatarApiError = avatarError is ApiException ? avatarError : null;
    // Reflects the live session user so a just-uploaded avatar shows
    // immediately, rather than the snapshot this screen was opened with.
    final currentAvatarUrl = ref
        .watch(sessionControllerProvider)
        .user
        ?.avatarUrl;

    ref.listen(editProfileControllerProvider, (previous, next) {
      final justSaved = previous?.isLoading == true && next.hasValue;
      if (justSaved) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
        context.pop();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: avatarState.isLoading ? null : _pickAvatar,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        UserAvatar(avatarUrl: currentAvatarUrl, radius: 48),
                        if (avatarState.isLoading)
                          const CircleAvatar(
                            radius: 48,
                            backgroundColor: Colors.black45,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          )
                        else
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              child: Icon(
                                Icons.camera_alt,
                                size: 18,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (avatarApiError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      avatarApiError.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    errorText: apiError?.messageForField('username'),
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'Username is required.';
                    if (v.length < 3) {
                      return 'Username must be at least 3 characters.';
                    }
                    if (v.length > 20) {
                      return 'Username must be at most 20 characters.';
                    }
                    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v)) {
                      return 'Only letters, numbers, and underscores.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bioController,
                  decoration: const InputDecoration(
                    labelText: 'About Me',
                    alignLabelWithHint: true,
                  ),
                  maxLength: 300,
                  maxLines: 4,
                  textInputAction: TextInputAction.done,
                  validator: (value) {
                    if ((value ?? '').length > 300) {
                      return 'About Me must be at most 300 characters.';
                    }
                    return null;
                  },
                ),
                if (apiError != null && apiError.fieldErrors.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      apiError.message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: state.isLoading ? null : _submit,
                  child: state.isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
