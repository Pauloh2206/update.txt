#!/usr/bin/env node

import fs from 'fs/promises';
import fsSync from 'fs';
import path from 'path';
import { exec } from 'child_process';
import os from 'os';
import { promisify } from 'util';
import { fileURLToPath } from 'url';

const execAsync = promisify(exec);
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const REPO_URL = 'https://github.com/hiudyy/nazuna.git';
const BACKUP_DIR = path.join(process.cwd(), `backup_${new Date().toISOString().replace(/[:.]/g, '_').replace(/T/, '_')}`);
const TEMP_DIR = path.join(process.cwd(), 'temp_nazuna');
const isWindows = os.platform() === 'win32';

// --- SUAS VARIÁVEIS DE CUSTOMIZAÇÃO ---
const MARKER_UPDATE = '// --- MINHA VERSÃO PERSONALIZADA UPDATE ---';
const MARKER_INDEX = '// --- MINHA VERSÃO PERSONALIZADA INDEX ---';
// ---------------------------------------

const colors = {
 reset: '\x1b[0m',
 green: '\x1b[1;32m',
 red: '\x1b[1;31m',
 blue: '\x1b[1;34m',
 yellow: '\x1b[1;33m',
 cyan: '\x1b[1;36m',
 magenta: '\x1b[1;35m',
 dim: '\x1b[2m',
 bold: '\x1b[1m',
};

function printMessage(text) {
 console.log(`${colors.green}${text}${colors.reset}`);
}

function printWarning(text) {
 console.log(`${colors.red}${text}${colors.reset}`);
}

function printInfo(text) {
 console.log(`${colors.cyan}${text}${colors.reset}`);
}

function printDetail(text) {
 console.log(`${colors.dim}${text}${colors.reset}`);
}

function printSeparator() {
 console.log(`${colors.blue}============================================${colors.reset}`);
}

async function verifyFileContent(filePath, expectedString) {
  if (!fsSync.existsSync(filePath)) {
    return false;
  }
  try {
    const contents = await fs.readFile(filePath, 'utf8');
    return contents.includes(expectedString);
  } catch (error) {
    return false;
  }
}

async function cleanupOldBackups() {
  printInfo('🧹 Verificando e removendo backups antigos...');
  try {
    const items = await fs.readdir(process.cwd());
    const backupPattern = /^backup_\d{4}-\d{2}-\d{2}_/; // Padrão 'backup_YYYY-MM-DD_'

    for (const item of items) {
      if (backupPattern.test(item)) {
        const fullPath = path.join(process.cwd(), item);
        if (fsSync.statSync(fullPath).isDirectory()) {
          // Evita deletar o diretório de backup atual
          if (fullPath !== BACKUP_DIR) {
           printDetail(`🗑️ Removendo backup antigo: ${item}`);
           await fs.rm(fullPath, { recursive: true, force: true });
          }
        }
      }
    }
    printDetail('✅ Limpeza de backups antigos concluída.');
  } catch (error) {
    printWarning(`⚠️ Erro ao limpar backups antigos: ${error.message}`);
  }
}


function setupGracefulShutdown() {
 const shutdown = () => {
  console.log('\n');
  printWarning('🛑 Atualização cancelada pelo usuário.');
  process.exit(0);
 };

 process.on('SIGINT', shutdown);
 process.on('SIGTERM', shutdown);
}

async function displayHeader() {
 const header = [
  `${colors.bold}🚀 Shania Yan (Nazu) - Atualizador${colors.reset}`,
  `${colors.bold}👨‍💻 Adaptado por Paulo${colors.reset}`,
 ];

 printSeparator();
 for (const line of header) {
  process.stdout.write(line + '\n');
 }
 printSeparator();
 console.log();
}

async function checkRequirements() {
 printInfo('🔍 Verificando requisitos do sistema...');

 try {
  await execAsync('git --version');
  printDetail('✅ Git encontrado.');
 } catch (error) {
  printWarning('⚠️ Git não encontrado! É necessário para atualizar o Nazuna.');
  if (isWindows) {
   printInfo('📥 Instale o Git em: https://git-scm.com/download/win');
  } else if (os.platform() === 'darwin') {
   printInfo('📥 Instale o Git com: brew install git');
  } else {
   printInfo('📥 Instale o Git com: sudo apt-get install git (Ubuntu/Debian) ou equivalente.');
  }
  process.exit(1);
 }

 try {
  await execAsync('npm --version');
  printDetail('✅ NPM encontrado.');
 } catch (error) {
  printWarning('⚠️ NPM não encontrado! É necessário para instalar dependências.');
  printInfo('📥 Instale o Node.js e NPM em: https://nodejs.org');
  process.exit(1);
 }

 printDetail('✅ Todos os requisitos atendidos.');
}

async function confirmUpdate() {
 printWarning('⚠️ Atenção: A atualização sobrescreverá arquivos existentes, exceto configurações e dados salvos.');
 printInfo('📂 Um backup será criado automaticamente.');
 printWarning('🛑 Pressione Ctrl+C para cancelar a qualquer momento.');

 return new Promise((resolve) => {
  let countdown = 5;
  const timer = setInterval(() => {
   process.stdout.write(`\r⏳ Iniciando em ${countdown} segundos...${' '.repeat(20)}`);
   countdown--;

   if (countdown < 0) {
    clearInterval(timer);
    process.stdout.write('\r                 \n');
    printMessage('🚀 Prosseguindo com a atualização...');
    resolve();
   }
  }, 1000);
 });
}

// --- FUNÇÃO createBackup (MELHORADA POR PAULO - package.json incluído) ---
async function createBackup() {
 // Limpa backups antigos antes de criar o novo (Sua função)
 await cleanupOldBackups();

 printMessage('📁 Criando backup dos arquivos...');

 try {
  // Validate backup directory path
  if (!BACKUP_DIR || BACKUP_DIR.includes('..')) {
   throw new Error('Caminho de backup inválido');
  }

  // Criação dos diretórios no backup.
  await fs.mkdir(path.join(BACKUP_DIR, 'dados', 'database'), { recursive: true });
  await fs.mkdir(path.join(BACKUP_DIR, 'dados', 'src', '.scripts'), { recursive: true }); // Novo diretório para update.js
  await fs.mkdir(path.join(BACKUP_DIR, 'dados', 'midias'), { recursive: true });

  const databaseDir = path.join(process.cwd(), 'dados', 'database');
  if (fsSync.existsSync(databaseDir)) {
   printDetail('📂 Copiando diretório de banco de dados...');
   try {
    await fs.access(databaseDir);
    await fs.cp(databaseDir, path.join(BACKUP_DIR, 'dados', 'database'), { recursive: true });
   } catch (accessError) {
    printWarning(`⚠️ Não foi possível acessar o diretório de banco de dados: ${accessError.message}`);
    throw new Error('Falha ao acessar diretório de dados para backup');
   }
  }

  const configFile = path.join(process.cwd(), 'dados', 'src', 'config.json');
  if (fsSync.existsSync(configFile)) {
   printDetail('📝 Copiando arquivo de configuração...');
   try {
    await fs.access(configFile, fsSync.constants.R_OK);
    await fs.copyFile(configFile, path.join(BACKUP_DIR, 'dados', 'src', 'config.json'));
   } catch (accessError) {
    printWarning(`⚠️ Não foi possível acessar o arquivo de configuração: ${accessError.message}`);
    throw new Error('Falha ao acessar arquivo de configuração para backup');
   }
  }

  // CUSTOMIZADO: Copiando dados/src/.scripts/update.js
  const updateScriptFile = path.join(process.cwd(), 'dados', 'src', '.scripts', 'update.js');
  const backupUpdatePath = path.join(BACKUP_DIR, 'dados', 'src', '.scripts', 'update.js');
  if (fsSync.existsSync(updateScriptFile)) {
   printDetail('📝 Copiando dados/src/.scripts/update.js (Personalizado)...');
   try {
    await fs.access(updateScriptFile, fsSync.constants.R_OK);
    await fs.copyFile(updateScriptFile, backupUpdatePath);

    if (await verifyFileContent(backupUpdatePath, MARKER_UPDATE)) {
      printDetail(` => ✅ Backup OK: update.js contém a string de marcador.`);
    } else {
      printWarning(` => ❌ ATENÇÃO: update.js NO BACKUP NÃO CONTÉM O MARCADOR. Verifique.`);
    }
   } catch (accessError) {
    printWarning(`⚠️ Falha ao copiar update.js: ${accessError.message}`);
   }
  }
 
  // CUSTOMIZADO: Copiando dados/src/index.js
  const indexFile = path.join(process.cwd(), 'dados', 'src', 'index.js');
  const backupIndexPath = path.join(BACKUP_DIR, 'dados', 'src', 'index.js');
  if (fsSync.existsSync(indexFile)) {
   printDetail('📝 Copiando dados/src/index.js (Personalizado)...');
   try {
    await fs.access(indexFile, fsSync.constants.R_OK);
    await fs.copyFile(indexFile, backupIndexPath);

    if (await verifyFileContent(backupIndexPath, MARKER_INDEX)) {
      printDetail(` => ✅ Backup OK: index.js contém a string de marcador.`);
    } else {
      printWarning(` => ❌ ATENÇÃO: index.js NO BACKUP NÃO CONTÉM O MARCADOR. Verifique.`);
    }

   } catch (accessError) {
    printWarning(`⚠️ Falha ao copiar index.js: ${accessError.message}`);
   }
  }

    // NOVO: Backup do package.json (na raiz do backup)
    const packageJsonFile = path.join(process.cwd(), 'package.json');
    if (fsSync.existsSync(packageJsonFile)) {
        printDetail('📝 Copiando package.json...');
        try {
            await fs.access(packageJsonFile, fsSync.constants.R_OK);
            await fs.copyFile(packageJsonFile, path.join(BACKUP_DIR, 'package.json'));
        } catch (accessError) {
            printWarning(`⚠️ Não foi possível acessar o package.json: ${accessError.message}`);
            throw new Error('Falha ao acessar package.json para backup');
        }
    }

  const midiasDir = path.join(process.cwd(), 'dados', 'midias');
  if (fsSync.existsSync(midiasDir)) {
   printDetail('🖼️ Copiando diretório de mídias...');
   try {
    await fs.access(midiasDir);
    await fs.cp(midiasDir, path.join(BACKUP_DIR, 'dados', 'midias'), { recursive: true });
   } catch (accessError) {
    printWarning(`⚠️ Não foi possível acessar o diretório de mídias: ${accessError.message}`);
    throw new Error('Falha ao acessar diretório de mídias para backup');
   }
  }

  // Verifica se os backups cruciais foram criados
  const backupSuccess = (
   fsSync.existsSync(path.join(BACKUP_DIR, 'dados', 'database')) ||
   fsSync.existsSync(path.join(BACKUP_DIR, 'dados', 'src', 'config.json'))
  );

  if (!backupSuccess) {
   throw new Error('Backup incompleto - dados cruciais não foram copiados');
  }

  printMessage(`✅ Backup salvo em: ${BACKUP_DIR}`);
 } catch (error) {
  printWarning(`❌ Erro ao criar backup: ${error.message}`);
  printInfo('📝 A atualização será cancelada para evitar perda de dados.');
  throw error;
 }
}
// --- FIM createBackup ---

async function downloadUpdate() {
 printMessage('📥 Baixando a versão mais recente do Nazuna...');

 try {
  if (!TEMP_DIR || TEMP_DIR.includes('..')) {
   throw new Error('Caminho de diretório temporário inválido');
  }

  if (fsSync.existsSync(TEMP_DIR)) {
   printDetail('🔄 Removendo diretório temporário existente...');
   try {
    await fs.rm(TEMP_DIR, { recursive: true, force: true });
   } catch (rmError) {
    printWarning(`⚠️ Não foi possível remover diretório temporário existente: ${rmError.message}`);
    throw new Error('Falha ao limpar diretório temporário');
   }
  }

  printDetail('🔄 Clonando repositório...');
  let gitProcess;
  try {
   gitProcess = exec(`git clone --depth 1 ${REPO_URL} "${TEMP_DIR}"`, (error) => {
    if (error) {
     // O tratamento principal está no 'close'
    }
   });
  } catch (execError) {
   printWarning(`❌ Falha ao iniciar processo Git: ${execError.message}`);
   throw new Error('Falha ao iniciar processo de download');
  }

  const spinner = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
  let i = 0;
  const interval = setInterval(() => {
   process.stdout.write(`\r${spinner[i]} Baixando...`);
   i = (i + 1) % spinner.length;
  }, 100);

  return new Promise((resolve, reject) => {
   gitProcess.on('close', async (code) => {
    clearInterval(interval);
    process.stdout.write('\r        \r');
   
    if (code !== 0) {
     printWarning(`❌ Git falhou com código de saída ${code}`);
     reject(new Error(`Git clone failed with exit code ${code}`));
     return;
    }

    if (!fsSync.existsSync(TEMP_DIR)) {
     reject(new Error('Diretório temporário não foi criado após o clone'));
     return;
    }

    const gitDir = path.join(TEMP_DIR, '.git');
    if (!fsSync.existsSync(gitDir)) {
     reject(new Error('Clone do repositório Git inválido'));
     return;
    }

    try {
     const readmePath = path.join(TEMP_DIR, 'README.md');
     if (fsSync.existsSync(readmePath)) {
      await fs.unlink(readmePath);
     }
    } catch (unlinkError) {
     printWarning(`⚠️ Não foi possível remover README.md: ${unlinkError.message}`);
    }

    printMessage('✅ Download concluído com sucesso.');
    resolve();
   });

   gitProcess.on('error', (error) => {
    clearInterval(interval);
    process.stdout.write('\r        \r');
    printWarning(`❌ Erro no processo Git: ${error.message}`);
    reject(error);
   });
  });
 } catch (error) {
  printWarning(`❌ Falha ao baixar a atualização: ${error.message}`);
  printInfo('🔍 Verificando conectividade com o GitHub...');
  try {
   await execAsync(isWindows ? 'ping github.com -n 1' : 'ping -c 1 github.com');
   printWarning('⚠️ Verifique permissões ou configuração do Git.');
  } catch {
   printWarning('⚠️ Sem conexão com a internet. Verifique sua rede.');
  }
  throw error;
 }
}

// --- FUNÇÃO cleanOldFiles (ADAPTADA para incluir limpeza de customizados) ---
async function cleanOldFiles(options = {}) {
 const { removeNodeModules = true, removePackageLock = true } = options;
 printMessage('🧹 Limpando arquivos antigos...');

 try {
  const itemsToDelete = [
   { path: path.join(process.cwd(), '.git'), type: 'dir', name: '.git' },
   { path: path.join(process.cwd(), '.github'), type: 'dir', name: '.github' },
   { path: path.join(process.cwd(), '.npm'), type: 'dir', name: '.npm' },
   { path: path.join(process.cwd(), 'README.md'), type: 'file', name: 'README.md' },
  ];

  if (removeNodeModules) {
   itemsToDelete.push({ path: path.join(process.cwd(), 'node_modules'), type: 'dir', name: 'node_modules' });
  } else {
   printDetail('🛠️ Mantendo node_modules existente.');
  }

  if (removePackageLock) {
   itemsToDelete.push({ path: path.join(process.cwd(), 'package-lock.json'), type: 'file', name: 'package-lock.json' });
  } else {
   printDetail('🛠️ Mantendo package-lock.json existente.');
  }

  for (const item of itemsToDelete) {
   if (fsSync.existsSync(item.path)) {
    printDetail(`📂 Removendo ${item.name}...`);
    if (item.type === 'dir') {
     await fs.rm(item.path, { recursive: true, force: true });
    } else {
     await fs.unlink(item.path);
    }
   }
  }

  const dadosDir = path.join(process.cwd(), 'dados');
  if (fsSync.existsSync(dadosDir)) {
   printDetail('📂 Preservando diretório de dados...');
  
   // Inclui a limpeza dos arquivos customizados antes de aplicar a nova versão
   const filesToClean = [
    'src/config.json', // Será restaurado do backup
    'src/.scripts',  // Diretório de scripts antigos (do repo original)
    'src/index.js',  // Arquivo customizado
   ];
  
   for (const fileToClean of filesToClean) {
    const filePath = path.join(dadosDir, fileToClean);
    if (fsSync.existsSync(filePath)) {
     printDetail(`📂 Removendo arquivo/diretório antigo: ${fileToClean}...`);
     if (fsSync.statSync(filePath).isDirectory()) {
      await fs.rm(filePath, { recursive: true, force: true });
     } else {
      await fs.unlink(filePath);
     }
    }
   }
  
   printDetail('✅ Diretório de dados preservado com sucesso.');
  }

  printMessage('✅ Limpeza concluída com sucesso.');
 } catch (error) {
  printWarning(`❌ Erro ao limpar arquivos antigos: ${error.message}`);
  throw error;
 }
}
// --- FIM cleanOldFiles ---


async function applyUpdate() {
 printMessage('🚀 Aplicando atualização...');

 try {
  // Copia o novo código do temporário para o diretório de trabalho
  await fs.cp(TEMP_DIR, process.cwd(), { recursive: true });

  // Remove o diretório temporário após a cópia
  await fs.rm(TEMP_DIR, { recursive: true, force: true });

  printMessage('✅ Atualização aplicada com sucesso.');
 } catch (error) {
  printWarning(`❌ Erro ao aplicar atualização: ${error.message}`);
  throw error;
 }
}

// --- FUNÇÃO restoreBackup (MELHORADA POR PAULO - package.json incluído) ---
async function restoreBackup() {
 printMessage('📂 Restaurando backup...');

 try {
  // Cria os diretórios necessários na instalação atual
  await fs.mkdir(path.join(process.cwd(), 'dados', 'database'), { recursive: true });
  await fs.mkdir(path.join(process.cwd(), 'dados', 'src', '.scripts'), { recursive: true });
  await fs.mkdir(path.join(process.cwd(), 'dados', 'midias'), { recursive: true });

  // Restaura o database
  const backupDatabaseDir = path.join(BACKUP_DIR, 'dados', 'database');
  if (fsSync.existsSync(backupDatabaseDir)) {
   printDetail('📂 Restaurando banco de dados...');
   await fs.cp(backupDatabaseDir, path.join(process.cwd(), 'dados', 'database'), { recursive: true });
  }

  // Restaura o config.json
  const backupConfigFile = path.join(BACKUP_DIR, 'dados', 'src', 'config.json');
  if (fsSync.existsSync(backupConfigFile)) {
   printDetail('📝 Restaurando arquivo de configuração...');
   await fs.copyFile(backupConfigFile, path.join(process.cwd(), 'dados', 'src', 'config.json'));
  }

    // NOVO: Restaura o package.json
    const backupPackageJsonFile = path.join(BACKUP_DIR, 'package.json');
    if (fsSync.existsSync(backupPackageJsonFile)) {
        printDetail('📝 Restaurando package.json...');
        await fs.copyFile(backupPackageJsonFile, path.join(process.cwd(), 'package.json'));
    }

  // CUSTOMIZADO: Restaura dados/src/.scripts/update.js
  const backupUpdateScriptFile = path.join(BACKUP_DIR, 'dados', 'src', '.scripts', 'update.js');
  const targetUpdatePath = path.join(process.cwd(), 'dados', 'src', '.scripts', 'update.js');
  if (fsSync.existsSync(backupUpdateScriptFile)) {
   printDetail('📝 Restaurando dados/src/.scripts/update.js (Personalizado)...');
   await fs.copyFile(backupUpdateScriptFile, targetUpdatePath);
  }
 
  // CUSTOMIZADO: Restaura dados/src/index.js
  const backupIndexFile = path.join(BACKUP_DIR, 'dados', 'src', 'index.js');
  const targetIndexPath = path.join(process.cwd(), 'dados', 'src', 'index.js');
  if (fsSync.existsSync(backupIndexFile)) {
   printDetail('📝 Restaurando dados/src/index.js (Personalizado)...');
   await fs.copyFile(backupIndexFile, targetIndexPath);
  }

  // Restaura as mídias
  const backupMidiasDir = path.join(BACKUP_DIR, 'dados', 'midias');
  if (fsSync.existsSync(backupMidiasDir)) {
   printDetail('🖼️ Restaurando diretório de mídias...');
   await fs.cp(backupMidiasDir, path.join(process.cwd(), 'dados', 'midias'), { recursive: true });
  }

  printMessage('✅ Backup restaurado com sucesso.');
 } catch (error) {
  printWarning(`❌ Erro ao restaurar backup: ${error.message}`);
  throw error;
 }
}
// --- FIM restoreBackup ---

async function checkDependencyChanges() {
 printInfo('🔍 Verificando mudanças nas dependências...');

 try {
  const currentPackageJsonPath = path.join(process.cwd(), 'package.json');
  const newPackageJsonPath = path.join(TEMP_DIR, 'package.json');
  // Se o package.json for restaurado, ele usará o antigo, então o teste é apenas de presença
  if (!fsSync.existsSync(currentPackageJsonPath)) {
   printDetail('📦 Arquivo package.json não encontrado, instalação será necessária');
   return 'MISSING_PACKAGE_JSON';
  }

    // O código abaixo checa se as dependências do OLD package.json (que será restaurado) estão presentes.
    // A comparação direta com o NEW package.json (no TEMP_DIR) é descartada, pois vamos restaurar o OLD.

  const currentPackage = JSON.parse(await fs.readFile(currentPackageJsonPath, 'utf8'));
  const nodeModulesPath = path.join(process.cwd(), 'node_modules');
  if (!fsSync.existsSync(nodeModulesPath)) {
   printDetail('📦 node_modules não encontrado, instalação necessária');
   return 'MISSING_NODE_MODULES';
  }
  const allDeps = Object.keys({
   ...currentPackage.dependencies,
   ...currentPackage.devDependencies,
   ...currentPackage.optionalDependencies
  });
  for (const depName of allDeps) {
   const depPath = path.join(nodeModulesPath, depName);
   if (!fsSync.existsSync(depPath)) {
    printDetail(`📦 Dependência não encontrada: ${depName}`);
    return 'MISSING_DEPENDENCIES';
   }
  }
  printDetail('✅ Todas as dependências do package.json atual estão presentes.');
    // Retornamos 'NO_CHANGES' aqui para pular a instalação, se já estiver tudo ok.
    // Lembre-se: se o repo original adicionou dependências, elas NÃO serão instaladas.
  return 'NO_CHANGES'; 
 } catch (error) {
  printWarning(`❌ Erro ao verificar dependências: ${error.message}`);
  return 'ERROR';
 }
}

async function installDependencies(precomputedResult) {
 const checkResult = precomputedResult ?? await checkDependencyChanges();
 // Se for 'NO_CHANGES' ou erro, o novo package.json foi sobrescrito pelo antigo.
 if (checkResult === 'NO_CHANGES') {
  printMessage('⚡ Dependências já estão atualizadas, pulando instalação');
  return;
 }
 printMessage('📦 Instalando dependências (baseado no seu package.json restaurado)...');
 try {
  await new Promise((resolve, reject) => {
   const npmProcess = exec('npm run config:install', { shell: isWindows }, (error) =>
    error ? reject(error) : resolve()
   );
   const spinner = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'];
   let i = 0;
   const interval = setInterval(() => {
    process.stdout.write(`\r${spinner[i]} Instalando dependências...`);
    i = (i + 1) % spinner.length;
   }, 100);
   npmProcess.on('close', (code) => {
    clearInterval(interval);
    process.stdout.write('\r                \r');
    if (code === 0) {
     resolve();
    } else {
     reject(new Error(`NPM install failed with exit code ${code}`));
    }
   });
  });
  const nodeModulesPath = path.join(process.cwd(), 'node_modules');
  if (!fsSync.existsSync(nodeModulesPath)) {
   throw new Error('Diretório node_modules não foi criado após a instalação');
  }
  printMessage('✅ Dependências instaladas com sucesso.');
 } catch (error) {
  printWarning(`❌ Falha ao instalar dependências: ${error.message}`);
  printInfo('📝 Tente executar manualmente: npm run config:install');
  throw error;
 }
}

// --- FUNÇÃO cleanupTempDir (SUA FUNÇÃO DE LIMPEZA DE TEMP) ---
async function cleanupTempDir() {
 printMessage('🧹 Limpando diretório temporário de download...');

 try {
  if (fsSync.existsSync(TEMP_DIR)) {
    await fs.rm(TEMP_DIR, { recursive: true, force: true });
    printDetail('✅ Diretório temporário removido.');
  }
 } catch (error) {
  printWarning(`❌ Erro ao limpar arquivos temporários: ${error.message}`);
 }
}

async function main() {
 let backupCreated = false;
 let downloadSuccessful = false;
 let updateApplied = false;
 let dependencyCheckResult = null;

 try {
  setupGracefulShutdown();
  await displayHeader();
  await checkRequirements();
  await confirmUpdate();

  // 1. BACKUP (package.json incluído)
  await createBackup();
  backupCreated = true;
  if (!fsSync.existsSync(BACKUP_DIR)) throw new Error('Falha ao criar diretório de backup');
 
  // 2. DOWNLOAD
  await downloadUpdate();
  downloadSuccessful = true;
  if (!fsSync.existsSync(TEMP_DIR)) throw new Error('Falha ao baixar atualização');
 
  // 3. VERIFICAR E LIMPAR
  dependencyCheckResult = await checkDependencyChanges();
    // Forçamos a remoção dos node_modules se a verificação falhou ou se o package.json foi restaurado (para garantir a limpeza antes da nova instalação)
  const shouldRemoveModules = dependencyCheckResult !== 'NO_CHANGES'; 
  await cleanOldFiles({
   removeNodeModules: shouldRemoveModules,
   removePackageLock: shouldRemoveModules,
  });
 
  // 4. APLICAR ATUALIZAÇÃO
  await applyUpdate();
  updateApplied = true;
  const newPackageJson = path.join(process.cwd(), 'package.json');
  if (!fsSync.existsSync(newPackageJson)) throw new Error('Falha ao aplicar atualização - package.json ausente');
 
  // 5. RESTAURAR DADOS (package.json restaurado aqui)
  await restoreBackup();
 
  // 6. INSTALAR DEPENDÊNCIAS (Baseado no package.json restaurado)
  await installDependencies(dependencyCheckResult);
 
  // 7. LIMPEZA FINAL: Remove o temporário
  await cleanupTempDir();
 
  printMessage('🧹 Removendo backup temporário de sucesso...');
  try {
    await fs.rm(BACKUP_DIR, { recursive: true, force: true });
    printDetail(`✅ Backup removido: ${path.basename(BACKUP_DIR)}`);
  } catch (error) {
    printWarning(`⚠️ Erro ao remover o backup. Ele pode ser deletado manualmente em: ${BACKUP_DIR}`);
  }
 
  // 8. PUXAR LOGS DE VERSÃO (COM TRATAMENTO DE ERRO NÃO-CRÍTICO)
  printMessage('🔄 Buscando informações do último commit...');
  try {
    const response = await fetch('https://api.github.com/repos/hiudyy/nazuna/commits?per_page=1', {
     headers: { Accept: 'application/vnd.github+json' },
    });
    if (!response.ok) {
     throw new Error(`Erro ao buscar commits: ${response.status} ${response.statusText}`);
    }
    const linkHeader = response.headers.get('link');
    const NumberUp = linkHeader?.match(/page=(\d+)>;\s*rel="last"/)?.[1];
    const jsonUp = { total: Number(NumberUp) || 0 };
    await fs.writeFile(path.join(process.cwd(), 'dados', 'database', 'updateSave.json'), JSON.stringify(jsonUp));
    printDetail('✅ updateSave.json atualizado.');

  } catch (error) {
    // O erro é tratado como AVISO, não como falha crítica.
    printWarning(`⚠️ Não foi possível registrar a versão (updateSave.json): ${error.message}`);
    printInfo('📝 Sua atualização foi aplicada, mas o arquivo de registro de versão pode estar desatualizado.');
  }
 
  printSeparator();
  printMessage('🎉 Atualização concluída com sucesso!');
  printWarning('🚨 Lembre-se de verificar se o repositório original adicionou novas dependências ao package.json!');
  printMessage('🚀 Inicie o bot com: npm start');
  printSeparator();
 } catch (error) {
  printSeparator();
  printWarning(`❌ Erro durante a atualização: ${error.message}`);
 
  // Recuperação de erro aprimorada
  if (backupCreated && !updateApplied) {
   try {
    await restoreBackup();
    printInfo('📂 Backup da versão antiga restaurado automaticamente.');
   } catch (restoreError) {
    printWarning(`❌ Falha ao restaurar backup automaticamente: ${restoreError.message}`);
   }
  } else if (backupCreated && downloadSuccessful && !updateApplied) {
   printWarning('⚠️ Download concluído, mas atualização não foi aplicada.');
   printInfo('🔄 Você pode tentar aplicar a atualização manualmente do diretório temporário.');
  } else if (!backupCreated) {
   printWarning('⚠️ Nenhum backup foi criado. Se houve falha, seus dados podem estar corrompidos.');
  }
 
  // Limpa apenas o TEMP_DIR, preservando o BACKUP_DIR para inspeção manual
  await cleanupTempDir();

  printWarning(`📂 Backup disponível em: ${BACKUP_DIR || 'Indisponível'}`);
  printInfo('📝 Para restaurar manualmente, copie os arquivos do backup para os diretórios correspondentes.');
  printInfo('📩 Em caso de dúvidas, contate o desenvolvedor.');
 
  process.exit(1);
 }
}

main();