# ADR 0004 — Interface SwiftUI commune iOS/Android

## Décision

L’interface utilise uniquement les composants SwiftUI exposés par Skip Fuse :
`TabView`, `NavigationStack`, `List`, `ScrollView`, `LazyVStack`, `Form`,
`TextField`, `SecureField`, `Toggle`, `Picker`, `Label`, les formes SwiftUI et
les symboles système courants.

Les couleurs, la typographie et les surfaces utilisent les valeurs
sémantiques SwiftUI afin de rester lisibles en mode sombre. Les icônes restent
des symboles SF courants ; Skip les remplace par les équivalents Android
disponibles. Aucun `UIImage`, `UIColor`, `PhotosPicker`, effet iOS spécifique
ou API Liquid Glass n’est utilisé.

## Écarts restants

- Les icônes peuvent avoir un dessin légèrement différent sur Android, car
  elles sont rendues par le jeu d’icônes de la plateforme.
- Le bouton pièce jointe est volontairement un placeholder jusqu’au branchement
  du sélecteur de médias partagé.
- Les données d’exemple ne servent qu’à rendre les écrans lisibles tant que la
  synchronisation des conversations n’est pas branchée.
