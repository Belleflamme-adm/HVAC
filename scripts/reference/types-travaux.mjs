// Liste de prix des sous-traitants (ADR-060) : tous les travaux qu'on leur demande de chiffrer.
// Source unique : génère la migration (node scripts/reference/generer-types-travaux.mjs) et alimente
// le HTML de test. Le code INST-TETE-MULTI reprend celui qui existe déjà dans la liste de prix de Mike.
// unite : forfait | tete | pied | sortie | heure | unite | livre
// Tout ce qui touche l'électricité, le gaz et les réfrigérants exige des licences : à valider par un professionnel.

export const CATEGORIES = [
  ['murale', 'Thermopompe murale | installation neuve'],
  ['tetes', 'Têtes intérieures spéciales (supplément par tête)'],
  ['central', 'Système central | installation neuve'],
  ['remplacement', 'Remplacements'],
  ['bienergie', 'Biénergie'],
  ['huile', 'Conversion de l\'huile'],
  ['ventilation', 'Ventilation | échangeur d\'air'],
  ['extras', 'Extras et options d\'installation'],
  ['conduits', 'Conduits'],
  ['electricite', 'Électricité (maître électricien, licence CMEQ)'],
  ['gaz', 'Gaz naturel et propane (licence gaz requise)'],
  ['retrait', 'Retrait et disposition'],
  ['service', 'Service et entretien'],
];

const t = (categorie, code, nom, unite, inclus = null) => ({ categorie, code, nom, unite, inclus });

export const TYPES_TRAVAUX = [
  // Murale
  t('murale', 'INST-MURAL-1T-12', 'Murale 1 tête, jusqu\'à 12 000 BTU', 'forfait', 'Condenseur et 1 tête, 25 pi de ligne, support, drain par gravité, vide d\'air, mise en marche'),
  t('murale', 'INST-MURAL-1T-18', 'Murale 1 tête, 15 000 à 18 000 BTU', 'forfait', 'Comme 12 000 BTU'),
  t('murale', 'INST-MURAL-1T-24', 'Murale 1 tête, 24 000 BTU et plus', 'forfait', 'Comme 12 000 BTU, appareil plus lourd'),
  t('murale', 'INST-MULTI-2T', 'Multizone 2 têtes', 'forfait', 'Condenseur et 2 têtes, 25 pi de ligne par tête, supports, drains, mise en marche'),
  t('murale', 'INST-MULTI-3T', 'Multizone 3 têtes', 'forfait', 'Condenseur et 3 têtes, 25 pi de ligne par tête'),
  t('murale', 'INST-MULTI-4T', 'Multizone 4 têtes', 'forfait', 'Condenseur et 4 têtes, 25 pi de ligne par tête'),
  t('murale', 'INST-MULTI-5T', 'Multizone 5 têtes', 'forfait', 'Condenseur et 5 têtes, 25 pi de ligne par tête'),
  t('murale', 'INST-TETE-MULTI', 'Installation additionnelle par tête multizone', 'tete', 'Tête ajoutée à un condenseur multizone, 25 pi de ligne'),
  // Têtes spéciales
  t('tetes', 'INST-TETE-CASSETTE', 'Tête cassette au plafond', 'tete', 'Supplément par rapport à une tête murale'),
  t('tetes', 'INST-TETE-CONSOLE', 'Tête console au plancher', 'tete', 'Supplément par rapport à une tête murale'),
  t('tetes', 'INST-TETE-GAINABLE', 'Tête gainable (conduits courts dissimulés)', 'tete', 'Supplément, conduits courts et grilles inclus'),
  // Central neuf
  t('central', 'INST-CENTRAL-NEUF', 'Système central neuf avec réseau de conduits (maison sans conduits)', 'forfait', 'Fournaise ou unité de traitement d\'air, thermopompe, plenums, réseau principal ; sorties en sus (CONDUIT-SORTIE)'),
  t('central', 'INST-CENTRAL-TP-UTA', 'Thermopompe centrale et unité de traitement d\'air (conduits existants)', 'forfait', 'Raccord au réseau existant, serpentin, condenseur, mise en marche'),
  t('central', 'INST-ADDON', 'Add-on thermopompe centrale sur fournaise existante', 'forfait', 'Serpentin sur la fournaise, condenseur, 25 pi de ligne, mise en marche'),
  t('central', 'INST-CLIM-CENTRAL', 'Climatiseur central (sans chauffage)', 'forfait', 'Serpentin et condenseur, 25 pi de ligne'),
  t('central', 'INST-FOURNAISE-ELEC', 'Fournaise électrique neuve (conduits existants)', 'forfait', 'Raccord au réseau de conduits existant'),
  // Remplacements
  t('remplacement', 'REMP-MURAL-1T', 'Remplacement d\'une murale 1 tête', 'forfait', 'Retrait de l\'ancienne, récupération du réfrigérant, nouvelle installation ; lignes réutilisées si conformes'),
  t('remplacement', 'REMP-MULTI-COND', 'Remplacement d\'un condenseur multizone', 'forfait', 'Têtes existantes conservées'),
  t('remplacement', 'REMP-TETE', 'Remplacement d\'une tête intérieure', 'tete'),
  t('remplacement', 'REMP-TP-CENTRALE-COND', 'Remplacement du condenseur d\'une thermopompe centrale', 'forfait', 'Serpentin existant conservé'),
  t('remplacement', 'REMP-TP-CENTRALE', 'Remplacement complet d\'une thermopompe centrale', 'forfait', 'Condenseur et serpentin'),
  t('remplacement', 'REMP-FOURNAISE-ELEC', 'Remplacement d\'une fournaise électrique (électrique vers électrique)', 'forfait'),
  t('remplacement', 'REMP-FOURNAISE-ELEC-TP', 'Remplacement d\'une fournaise électrique et ajout d\'une thermopompe centrale', 'forfait'),
  t('remplacement', 'REMP-FOURNAISE-GAZ', 'Remplacement d\'une fournaise au gaz (gaz vers gaz)', 'forfait', 'Raccord gaz et évent en sus si modifiés'),
  t('remplacement', 'REMP-UTA', 'Remplacement d\'une unité de traitement d\'air', 'forfait'),
  // Biénergie
  t('bienergie', 'BIEN-GAZ-REMP-ADDON', 'Remplacement d\'une fournaise au gaz et add-on thermopompe (biénergie)', 'forfait', 'Nouvelle fournaise au gaz, serpentin, condenseur, contrôle biénergie'),
  t('bienergie', 'BIEN-GAZ-ADDON', 'Add-on thermopompe sur fournaise au gaz existante (biénergie)', 'forfait', 'Serpentin, condenseur, contrôle biénergie'),
  t('bienergie', 'BIEN-HUILE-ADDON', 'Add-on thermopompe sur fournaise à l\'huile existante (biénergie)', 'forfait', 'Serpentin, condenseur, contrôle biénergie'),
  t('bienergie', 'BIEN-PROPANE-ADDON', 'Add-on thermopompe sur fournaise au propane (biénergie)', 'forfait', 'Serpentin, condenseur, contrôle biénergie'),
  t('bienergie', 'BIEN-CONTROLE', 'Contrôle biénergie seul', 'unite', 'Sonde extérieure, relais et programmation'),
  // Conversion huile
  t('huile', 'CONV-HUILE-ELEC', 'Fournaise à l\'huile remplacée par une fournaise électrique', 'forfait', 'Retrait du brûleur et de la fournaise ; réservoir en sus'),
  t('huile', 'CONV-HUILE-ELEC-TP', 'Fournaise à l\'huile remplacée par une fournaise électrique et une thermopompe centrale', 'forfait', 'Réservoir en sus'),
  t('huile', 'RETRAIT-RESERVOIR-INT', 'Retrait et disposition d\'un réservoir d\'huile intérieur', 'forfait', 'Vidange, découpe, transport'),
  t('huile', 'RETRAIT-RESERVOIR-EXT', 'Retrait d\'un réservoir d\'huile extérieur hors sol', 'forfait', 'Réservoir enfoui : soumission spéciale'),
  // Ventilation
  t('ventilation', 'INST-ECHANGEUR-NEUF', 'Échangeur d\'air (VRC ou VRE) neuf avec conduits', 'forfait', 'Appareil, conduits, sorties murales, équilibrage'),
  t('ventilation', 'REMP-ECHANGEUR', 'Remplacement d\'un échangeur d\'air (conduits existants)', 'forfait', 'Retrait de l\'ancien, équilibrage'),
  t('ventilation', 'SERV-EQUILIBRAGE', 'Équilibrage d\'un échangeur d\'air', 'forfait'),
  // Extras
  t('extras', 'EXTRA-LIGNE-PI', 'Ligne frigorifique supplémentaire (au-delà de 25 pi)', 'pied'),
  t('extras', 'EXTRA-COUVRE-LIGNE-PI', 'Couvre-ligne (line hide)', 'pied'),
  t('extras', 'EXTRA-DRAIN-PI', 'Drain de condensat supplémentaire', 'pied'),
  t('extras', 'EXTRA-POMPE-COND', 'Pompe à condensat', 'unite'),
  t('extras', 'EXTRA-SUPPORT-MURAL', 'Support mural du condenseur', 'unite'),
  t('extras', 'EXTRA-SUPPORT-SOL', 'Base au sol ou pattes anti-neige', 'unite'),
  t('extras', 'EXTRA-SUPPORT-TOIT', 'Installation du condenseur sur un toit', 'forfait'),
  t('extras', 'EXTRA-PERCAGE-BETON', 'Percement béton ou fondation', 'unite'),
  t('extras', 'EXTRA-PERCAGE-BRIQUE', 'Percement brique ou pierre', 'unite'),
  t('extras', 'EXTRA-HAUTEUR', 'Travail en hauteur (2e étage et plus, échafaudage ou nacelle)', 'forfait'),
  t('extras', 'EXTRA-ACCES-DIFFICILE', 'Accès difficile (vide sanitaire, entretoit, plafond fini)', 'forfait'),
  t('extras', 'EXTRA-THERMOSTAT', 'Pose d\'un thermostat programmable ou intelligent', 'unite'),
  // Conduits
  t('conduits', 'CONDUIT-SORTIE', 'Sortie d\'alimentation (trappe) ajoutée', 'sortie'),
  t('conduits', 'CONDUIT-RETOUR', 'Retour d\'air ajouté', 'sortie'),
  t('conduits', 'CONDUIT-PLENUM', 'Fabrication ou modification d\'un plenum', 'forfait'),
  t('conduits', 'CONDUIT-PI', 'Conduit rigide supplémentaire', 'pied'),
  // Électricité
  t('electricite', 'ELEC-CIRCUIT-240', 'Circuit 240 V dédié (jusqu\'à 25 pi du panneau)', 'unite', 'Travaux par un maître électricien'),
  t('electricite', 'ELEC-SECTIONNEUR', 'Sectionneur extérieur', 'unite'),
  t('electricite', 'ELEC-CIRCUIT-PI', 'Câblage supplémentaire (au-delà de 25 pi)', 'pied'),
  t('electricite', 'ELEC-PANNEAU', 'Mise à niveau du panneau électrique', 'forfait', 'Soumission spéciale au besoin'),
  // Gaz
  t('gaz', 'GAZ-RACCORD', 'Raccordement gaz naturel ou propane', 'forfait'),
  t('gaz', 'GAZ-EVENT-PVC', 'Évent et prise d\'air PVC (fournaise haute efficacité)', 'forfait'),
  t('gaz', 'GAZ-CHEMISAGE', 'Chemisage de cheminée', 'forfait'),
  // Retrait
  t('retrait', 'RETRAIT-MURAL', 'Retrait d\'une thermopompe murale et récupération du réfrigérant', 'unite'),
  t('retrait', 'RETRAIT-CENTRAL', 'Retrait d\'un condenseur central et récupération du réfrigérant', 'unite'),
  t('retrait', 'RETRAIT-FOURNAISE', 'Retrait et disposition d\'une fournaise', 'unite'),
  // Service
  t('service', 'SERV-DEPLACEMENT', 'Appel de service (déplacement et première heure)', 'forfait'),
  t('service', 'SERV-HEURE', 'Heure additionnelle', 'heure'),
  t('service', 'SERV-ENTRETIEN-MURAL', 'Entretien annuel d\'une murale', 'tete'),
  t('service', 'SERV-ENTRETIEN-CENTRAL', 'Entretien annuel d\'un système central', 'forfait'),
  t('service', 'SERV-REFRIGERANT', 'Ajout de réfrigérant', 'livre', 'Technicien certifié (halocarbures)'),
];

export const UNITES = { forfait: 'forfait', tete: 'par tête', pied: 'par pied', sortie: 'par sortie', heure: 'par heure', unite: 'par unité', livre: 'par livre' };
