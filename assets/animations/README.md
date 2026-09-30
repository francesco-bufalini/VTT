# Shared token animation libraries

Questa cartella e' il punto di ingresso per librerie di animazione condivise dai
token riggati.

La pipeline non copia automaticamente asset esterni nel repository. Questo
evita sia duplicazioni sia problemi di licenza. Per asset redistribuibili si
possono importare, per esempio, librerie CC0 e convertirle/retargetarle in una
Godot AnimationLibrary (.tres o .res).

Schema previsto nel manifest di un token umanoide:

    "rig_type": "humanoid",
    "skeleton_profile": "humanoid",
    "animation_set": "humanoid_default",
    "animation_library": "res://assets/animations/humanoid_default.tres",
    "default_animation": "idle"

Godot importa i GLB riggati come scene con Skeleton3D/AnimationPlayer. Il
retargeting va configurato sullo skeleton importato usando BoneMap e
SkeletonProfileHumanoid; la stessa AnimationLibrary puo' poi essere riusata da
tutti i token con mapping compatibile.

Non aggiungere qui file Mixamo grezzi se il repository e' destinato alla
redistribuzione degli asset. Preferire librerie esplicitamente redistribuibili,
per esempio CC0.
